module Ast = Cafec_Typed_ast
module Expr = Ast.Expr
module Stmt = Ast.Stmt
module Type = Ast.Type
module Lang = Cafec_Parse.Lang
module Keyword = Cafec_Parse.Token.Keyword

exception Compiler_bug [@@deriving_inline sexp]

[@@@end]

type t =
  | Interpreter :
      { entrypoint : Types.Function_index.t option
      ; funcs : (Name.anyfix Name.t * Expr.Block.t) Array.t }
      -> t

let funcs (Interpreter {funcs; _}) = funcs

let entrypoint (Interpreter {entrypoint; _}) = entrypoint

module Value = struct
  include Types.Value

  type function_index = Types.Function_index.t

  let function_index_of_int = Types.Function_index.of_int

  let rec clone imm =
    let rclone x = ref (clone !x) in
    match imm with
    | Integer _ | Function _ | Reference _ | Constructor _
     |Nilary_variant _ | Builtin _ ->
        imm
    | Variant (idx, v) -> Variant (idx, ref (clone !v))
    | Tuple r -> Tuple (Array.map ~f:rclone r)
    | Record r -> Record (Array.map ~f:rclone r)

  let rec to_string v ctxt ~lang =
    match v with
    | Integer n -> Int.to_string n
    | Constructor idx ->
        String.concat
          [ "<constructor "
          ; Lang.keyword_to_string Keyword.Variant ~lang
          ; "::"
          ; Int.to_string idx ]
    | Nilary_variant idx ->
        Lang.keyword_to_string Keyword.Variant ~lang
        ^ "::"
        ^ Int.to_string idx
    | Reference place ->
        let (Types.Expr_result.Place.Place {is_mut; value}) = place in
        let pointer =
          if is_mut
          then "&" ^ Lang.keyword_to_string Keyword.Mut ~lang ^ " "
          else "&"
        in
        String.concat [pointer; "{"; to_string !value ctxt ~lang; "}"]
    | Variant (idx, v) ->
        String.concat
          [ Lang.keyword_to_string Keyword.Variant ~lang
          ; "::"
          ; Int.to_string idx
          ; "("
          ; to_string !v ctxt ~lang
          ; ")" ]
    | Builtin b ->
        let builtin_kw =
          Lang.keyword_to_string Keyword.Builtin ~lang
        in
        let builtin = Expr.Builtin.to_string b ~lang in
        String.concat [builtin_kw; "("; builtin; ")"]
    | Tuple fields ->
        let fields =
          let f e = to_string !e ctxt ~lang in
          String.concat_sequence ~sep:", "
            (Sequence.map ~f (Array.to_sequence fields))
        in
        String.concat ["("; fields; ")"]
    | Record fields ->
        let fields =
          let f idx e =
            String.concat
              [Int.to_string idx; " = "; to_string !e ctxt ~lang]
          in
          String.concat_sequence ~sep:"; "
            (Sequence.mapi ~f (Array.to_sequence fields))
        in
        String.concat ["{ "; fields; " }"]
    | Function n ->
        let name, _ = (funcs ctxt).((n :> int)) in
        String.concat
          [ "<"
          ; Lang.keyword_to_string Keyword.Func ~lang
          ; " "
          ; Name.to_ident_string name
          ; ">" ]
end

module Expr_result = struct
  include Types.Expr_result

  let to_value = function
    | Value value -> value
    | Place (Place.Place {value; _}) -> Value.clone !value

  let reference ~is_mut = function
    | Value _ -> raise Compiler_bug
    | Place (Place.Place {is_mut = place_is_mut; value}) ->
        let is_mut = place_is_mut && is_mut in
        let place = Place.Place {is_mut; value} in
        Value (Value.Reference place)

  let deref r =
    let r = to_value r in
    match r with
    | Value.Reference p -> Place p
    | _ -> raise Compiler_bug

  let assign (Place.Place {is_mut; value}) imm =
    assert is_mut ;
    value := imm
end

module Object = struct
  type t = Object : {is_mut : bool; value : Value.t ref} -> t

  let place (Object {is_mut; value}) =
    Expr_result.Place.Place {is_mut; value}

  let obj ~is_mut value =
    let value = ref value in
    Object {is_mut; value}
end

let make ast =
  let module D = Ast.Function_declaration in
  let seq = ref (Ast.function_seq ast) in
  let helper _ =
    match Sequence.next !seq with
    | None -> raise Compiler_bug
    | Some (((D.Declaration {name; _}, _), (expr, _)), rest) ->
        seq := rest ;
        (name, expr)
  in
  let entrypoint =
    match Ast.entrypoint ast with
    | Some idx -> Some (Types.Function_index.of_int idx)
    | None -> None
  in
  Interpreter
    { entrypoint
    ; funcs = Array.init (Ast.number_of_functions ast) ~f:helper }

let get_function ctxt ~name =
  match
    Array.findi (funcs ctxt) ~f:(fun _ (name', _) ->
        Name.equal name name' )
  with
  | None -> None
  | Some (n, _) -> Some (Value.function_index_of_int n)

let eval_builtin builtin args =
  if Array.length args <> 2
  then raise Compiler_bug
  else
    let a1 =
      match Expr_result.to_value args.(0) with
      | Value.Integer n -> n
      | _ -> raise Compiler_bug
    in
    let a2 =
      match Expr_result.to_value args.(1) with
      | Value.Integer n -> n
      | _ -> raise Compiler_bug
    in
    match builtin with
    | Expr.Builtin.Less_eq ->
        if a1 <= a2
        then Expr_result.Value (Value.Nilary_variant 1)
        else Expr_result.Value (Value.Nilary_variant 0)
    | Expr.Builtin.Add -> Expr_result.Value (Value.Integer (a1 + a2))
    | Expr.Builtin.Sub -> Expr_result.Value (Value.Integer (a1 - a2))
    | Expr.Builtin.Mul -> Expr_result.Value (Value.Integer (a1 * a2))

let call ctxt (idx : Value.function_index) (args : Value.t list) =
  let rec eval_block ctxt locals (Expr.Block.Block {stmts; expr}) =
    let f locals = function
      | Stmt.Expression e, _ ->
          ignore (eval ctxt locals e) ;
          locals
      | Stmt.Let {expr; binding}, _ ->
          let expr, _ = expr in
          let (Ast.Binding.Binding {is_mut; _}) = binding in
          let v = Expr_result.to_value (eval ctxt locals expr) in
          Object.obj ~is_mut v :: locals
    in
    let locals = Array.fold stmts ~f ~init:locals in
    match expr with
    | Some (e, _) -> eval ctxt locals e
    | None -> Expr_result.Value (Value.Tuple Array.empty)
  and eval ctxt locals e =
    let (Expr.Expr {variant; _}) = e in
    match variant with
    | Expr.Integer_literal n -> Expr_result.Value (Value.Integer n)
    | Expr.Tuple_literal xs ->
        let f (e, _) =
          ref (Expr_result.to_value (eval ctxt locals e))
        in
        let fields = Array.map ~f xs in
        Expr_result.Value (Value.Tuple fields)
    | Expr.Match {cond = cond, _; arms} -> (
      match Expr_result.to_value (eval ctxt locals cond) with
      | Value.Variant (index, value) ->
          let _, (code, _) = arms.(index) in
          let locals = Object.obj ~is_mut:false !value :: locals in
          eval_block ctxt locals code
      | Value.Nilary_variant index ->
          let _, (code, _) = arms.(index) in
          eval_block ctxt locals code
      | _ -> raise Compiler_bug )
    | Expr.Local (Expr.Local.Local {index; _}) ->
        Expr_result.Place (Object.place (List.nth_exn locals index))
    | Expr.Builtin b -> Expr_result.Value (Value.Builtin b)
    | Expr.Call ((e, _), args) -> (
      match Expr_result.to_value (eval ctxt locals e) with
      | Value.Function func ->
          let _, expr = (funcs ctxt).((func :> int)) in
          let ready_arg (arg, _) =
            let imm = Expr_result.to_value (eval ctxt locals arg) in
            (* we should actually be figuring out whether these should be mut *)
            Object.obj ~is_mut:false imm
          in
          let args =
            Sequence.to_list
              (Sequence.map ~f:ready_arg (Array.to_sequence args))
          in
          let ret = eval_block ctxt args expr in
          ret
      | Value.Constructor idx ->
          assert (Array.length args = 1) ;
          let arg =
            let arg, _ = args.(0) in
            Expr_result.to_value (eval ctxt locals arg)
          in
          Expr_result.Value (Value.Variant (idx, ref arg))
      | Value.Builtin b ->
          let f (e, _) = eval ctxt locals e in
          let args = Array.map ~f args in
          eval_builtin b args
      | _ -> raise Compiler_bug )
    | Expr.Block (b, _) -> eval_block ctxt locals b
    | Expr.Global_function i ->
        Expr_result.Value
          (Value.Function (Value.function_index_of_int i))
    | Expr.Constructor (_, idx) ->
        Expr_result.Value (Value.Constructor idx)
    | Expr.Nilary_variant (_, idx) ->
        Expr_result.Value (Value.Nilary_variant idx)
    | Expr.Reference (place, _) ->
        let is_mut =
          let module C = Type.Category in
          match Type.category (Expr.full_type place) with
          | C.Any (C.Place C.Mutable) -> true
          | C.Any (C.Place C.Immutable) -> false
          | C.Any (C.Place _) -> .
          | C.Any _ -> raise Compiler_bug
        in
        let place = eval ctxt locals place in
        Expr_result.reference ~is_mut place
    | Expr.Dereference (value, _) ->
        let value = eval ctxt locals value in
        Expr_result.deref value
    | Expr.Record_literal {fields; _} ->
        let f e = ref (Expr_result.to_value (eval ctxt locals e)) in
        let fields = Array.map ~f fields in
        Expr_result.Value (Value.Record fields)
    | Expr.Record_access ((e, _), idx) -> (
        let v = eval ctxt locals e in
        match v with
        | Expr_result.Value (Value.Record fields) ->
            Expr_result.Value !(fields.(idx))
        | Expr_result.(Place (Place.Place {value; is_mut})) -> (
          match !value with
          | Value.Record fields ->
              let value = fields.(idx) in
              Expr_result.(Place (Place.Place {value; is_mut}))
          | _ -> raise Compiler_bug )
        | _ -> raise Compiler_bug )
    | Expr.Assign {dest = dest, _; source = source, _} -> (
        let dest = eval ctxt locals dest in
        let source = Expr_result.to_value (eval ctxt locals source) in
        match dest with
        | Expr_result.Value _ -> raise Compiler_bug
        | Expr_result.Place place ->
            Expr_result.assign place source ;
            Expr_result.Value (Value.Tuple Array.empty) )
  in
  let _, blk = (funcs ctxt).((idx :> int)) in
  let args = List.map ~f:(Object.obj ~is_mut:false) args in
  Expr_result.to_value (eval_block ctxt args blk)
