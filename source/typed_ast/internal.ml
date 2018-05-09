module Span = Spanned.Span
module Untyped_ast = Cafec_parse.Ast
module Error = Error
module Expr = Expr
open Spanned.Result.Monad

module Function_declaration = struct
  type t = {name: string; params: (string * Type.t) list; ret_ty: Type.t}
end

(*
  NOTE: we may eventually want to do some sort of caching
  so we don't have to calculate types each time
*)
module Type_context = struct
  type t = (string * Untyped_ast.Type.t) list
end

module Function_context = struct
  type t = Function_declaration.t Spanned.t list
end

module Function_definitions = struct
  type t = Expr.t Spanned.t list
end

type t =
  { type_context: Type_context.t
  ; function_context: Function_context.t
  ; function_definitions: Function_definitions.t }

type 'a result = ('a, Error.t) Spanned.Result.t

module Types : sig
  val type_untyped : Type_context.t -> Untyped_ast.Type.t -> Type.t result
end = struct
  let rec type_untyped ctxt unt_ty =
    let module U = Untyped_ast.Type in
    match unt_ty with
    | U.Named name -> (
        let f (name', _) = String.equal name' name in
        match List.find ~f ctxt with
        | Some (_, ty) -> type_untyped ctxt ty
        | None ->
          match name with
          | "unit" -> return Type.Unit
          | "bool" -> return Type.Bool
          | "int" -> return Type.Int
          | name -> return_err (Error.Type_not_found name) )
    | U.Record members ->
        let rec map = function
          | [] -> return []
          | ((name, ty), sp) :: xs ->
              let%bind () = with_span sp in
              let%bind ty = type_untyped ctxt ty in
              let%bind rest = map xs in
              return ((name, ty) :: rest)
        in
        let%bind members = map members in
        return (Type.Record members)
    | U.Function (params, ret_ty) ->
        let rec map = function
          | [] -> return []
          | (ty, sp) :: xs ->
              let%bind () = with_span sp in
              let%bind ty = type_untyped ctxt ty in
              let%bind rest = map xs in
              return (ty :: rest)
        in
        let%bind params = map params in
        let%bind ret_ty =
          match ret_ty with
          | None -> return Type.Unit
          | Some (ty, _) -> type_untyped ctxt ty
        in
        return (Type.Function {params; ret_ty})
end

module Functions : sig
  val index_by_name : Function_context.t -> string -> int option

  val decl_by_index :
    Function_context.t -> int -> Function_declaration.t Spanned.t

  val expr_by_index : Function_definitions.t -> int -> Expr.t Spanned.t
end = struct
  let index_by_name ctxt search =
    let rec helper n = function
      | ({Function_declaration.name; _}, _) :: _ when String.equal name search ->
          Some n
      | _ :: names -> helper (n + 1) names
      | [] -> None
    in
    helper 0 ctxt


  let decl_by_index ctxt idx =
    let rec helper = function
      | 0, decl :: _ -> decl
      | n, _ :: decls -> helper (n - 1, decls)
      | _, [] -> assert false
    in
    if idx < 0 then assert false else helper (idx, ctxt)


  let expr_by_index func_defs idx =
    let rec helper = function
      | 0, expr :: _ -> expr
      | n, _ :: defs -> helper (n - 1, defs)
      | _, [] -> assert false
    in
    if idx < 0 then assert false else helper (idx, func_defs)
end

(* also typechecks *)
let rec type_of_expr (ctxt: t) (decl: Function_declaration.t)
    (e: Expr.t Spanned.t) : Type.t result =
  let e, sp = e in
  let%bind () = with_span sp in
  match e with
  | Expr.Unit_literal -> return Type.Unit
  | Expr.Bool_literal _ -> return Type.Bool
  | Expr.Integer_literal _ -> return Type.Int
  | Expr.If_else (cond, e1, e2) -> (
      match%bind type_of_expr ctxt decl cond with
      | Type.Bool ->
          let%bind t1 = type_of_expr ctxt decl e1 in
          let%bind t2 = type_of_expr ctxt decl e2 in
          if Type.equal t1 t2 then return t1
          else return_err (Error.If_branches_of_differing_type (t1, t2))
      | ty -> return_err (Error.If_non_bool ty) )
  | Expr.Call (callee, args) -> (
      let%bind ty_callee = type_of_expr ctxt decl callee in
      match ty_callee with
      | Type.Function {params; ret_ty} ->
          let%bind ty_args =
            let rec helper = function
              | [] -> return []
              | x :: xs ->
                  let%bind ty = type_of_expr ctxt decl x in
                  let%bind rest = helper xs in
                  return (ty :: rest)
            in
            helper args
          in
          if List.equal ty_args params ~equal:Type.equal then return ret_ty
          else
            return_err
              (Error.Invalid_function_arguments
                 {expected= params; found= ty_args})
      | ty -> return_err (Error.Call_of_non_function ty) )
  | Expr.Builtin b -> (
    match b with
    | Expr.Builtin.Add | Expr.Builtin.Sub | Expr.Builtin.Mul ->
        return Type.(Function {params= [Int; Int]; ret_ty= Int})
    | Expr.Builtin.Less_eq ->
        return Type.(Function {params= [Int; Int]; ret_ty= Bool}) )
  | Expr.Global_function f ->
      let decl, _ = Functions.decl_by_index ctxt.function_context f in
      let rec get_params = function
        | (_, x) :: xs -> x :: get_params xs
        | [] -> []
      in
      let params = get_params decl.Function_declaration.params in
      let ret_ty = decl.Function_declaration.ret_ty in
      return (Type.Function {params; ret_ty})
  | Expr.Parameter p ->
      let _, ty = List.nth_exn decl.Function_declaration.params p in
      return ty
  | Expr.Record_literal members -> (
      let compare ((name1, _), _) ((name2, _), _) =
        String.compare name1 name2
      in
      match List.find_a_dup ~compare members with
      | Some ((name, _), _) ->
          return_err (Error.Record_literal_duplicate_members name)
      | None ->
          let rec map = function
            | [] -> return []
            | ((name, e), _) :: xs ->
                let%bind ty = type_of_expr ctxt decl e in
                let%bind rest = map xs in
                return ((name, ty) :: rest)
          in
          let%bind members = map members in
          return (Type.Record members) )
  | Expr.Record_access (expr, name) ->
      let%bind ty = type_of_expr ctxt decl expr in
      match ty with
      | Type.Record members -> (
          let f (n, _) = String.equal n name in
          match List.find ~f members with
          | Some (_, ty) -> return ty
          | None -> return_err (Error.Record_access_non_member (ty, name)) )
      | ty -> return_err (Error.Record_access_non_record_type (ty, name))


let find_parameter name lst =
  let rec helper name lst idx =
    match lst with
    | [] -> None
    | (name', ty) :: _ when String.equal name' name -> Some (ty, idx)
    | _ :: xs -> helper name xs (idx + 1)
  in
  helper name lst 0


(* NOTE(ubsan): this does *not* typecheck *)
let rec type_expression decl ctxt unt_expr =
  let module U = Untyped_ast.Expr in
  let module T = Expr in
  let unt_expr, sp = unt_expr in
  let%bind () = with_span sp in
  match unt_expr with
  | U.Unit_literal -> return T.Unit_literal
  | U.Bool_literal b -> return (T.Bool_literal b)
  | U.Integer_literal i -> return (T.Integer_literal i)
  | U.If_else (cond, thn, els) ->
      let%bind cond = spanned_bind (type_expression decl ctxt cond) in
      let%bind thn = spanned_bind (type_expression decl ctxt thn) in
      let%bind els = spanned_bind (type_expression decl ctxt els) in
      return (T.If_else (cond, thn, els))
  | U.Call (callee, args) ->
      let%bind callee = spanned_bind (type_expression decl ctxt callee) in
      let rec helper = function
        | [] -> return []
        | x :: xs ->
            let%bind x = spanned_bind (type_expression decl ctxt x) in
            let%bind xs = helper xs in
            return (x :: xs)
      in
      let%bind args = helper args in
      return (T.Call (callee, args))
  | U.Variable name -> (
      let {Function_declaration.params; _} = decl in
      match find_parameter name params with
      | None -> (
        match Functions.index_by_name ctxt name with
        | None -> (
          match name with
          | "LESS_EQ" -> return (T.Builtin T.Builtin.Less_eq)
          | "ADD" -> return (T.Builtin T.Builtin.Add)
          | "SUB" -> return (T.Builtin T.Builtin.Sub)
          | "MUL" -> return (T.Builtin T.Builtin.Mul)
          | _ -> return_err (Error.Name_not_found name) )
        | Some idx -> return (T.Global_function idx) )
      | Some (_ty, idx) -> return (T.Parameter idx) )
  | U.Record_literal members ->
      let%bind members =
        let rec map (xs: (string * U.t Spanned.t) Spanned.t list) =
          match xs with
          | [] -> return []
          | ((name, expr), sp) :: xs ->
              let%bind expr = spanned_bind (type_expression decl ctxt expr) in
              let%bind xs = map xs in
              return (((name, expr), sp) :: xs)
        in
        map members
      in
      return (T.Record_literal members)
  | U.Record_access (expr, member) ->
      let%bind expr = spanned_bind (type_expression decl ctxt expr) in
      return (T.Record_access (expr, member))


let add_alias (ctxt: t) (unt_type: (string * Untyped_ast.Type.t) Spanned.t)
    : t result =
  let module T = Untyped_ast.Type in
  let rec duplicates search = function
    | [] -> false
    | (name, _) :: _ when String.equal name search -> true
    | _ :: xs -> duplicates search xs
  in
  let (name, uty), sp = unt_type in
  let%bind () = with_span sp in
  if duplicates name ctxt.type_context then
    return_err (Error.Defined_type_multiple_times name)
  else return {ctxt with type_context= (name, uty) :: ctxt.type_context}


let add_function_declaration (ctxt: t) (unt_func: Untyped_ast.Func.t Spanned.t)
    : t result =
  let module F = Untyped_ast.Func in
  let unt_func, _ = unt_func in
  let {F.name; F.params; F.ret_ty; _} = unt_func in
  let%bind params, parm_sp =
    let rec helper ctxt = function
      | [] -> return []
      | ((name, ty), _) :: xs ->
          let%bind ty = Types.type_untyped ctxt ty in
          let%bind tys = helper ctxt xs in
          return ((name, ty) :: tys)
    in
    spanned_bind (helper ctxt.type_context params)
  in
  let%bind ret_ty, rty_sp =
    match ret_ty with
    | Some (ret_ty, _) ->
        spanned_bind (Types.type_untyped ctxt.type_context ret_ty)
    | None -> return (Type.Unit, Span.made_up)
  in
  (* check for duplicates *)
  let rec check_for_duplicates search = function
    | [] -> None
    | (f, sp) :: _ when String.equal f.Function_declaration.name search ->
        Some (f, sp)
    | _ :: xs -> check_for_duplicates search xs
  in
  match check_for_duplicates name ctxt.function_context with
  | Some (_, sp) ->
      return_err
        (Error.Defined_function_multiple_times {name; original_declaration= sp})
  | None ->
      let decl =
        (Function_declaration.{name; params; ret_ty}, Span.union parm_sp rty_sp)
      in
      return {ctxt with function_context= decl :: ctxt.function_context}


let add_function_definition (ctxt: t) (unt_func: Untyped_ast.Func.t Spanned.t)
    : t result =
  let module F = Untyped_ast.Func in
  let unt_func, _ = unt_func in
  let decl =
    let num_funcs = List.length ctxt.function_context in
    let idx = num_funcs - 1 - List.length ctxt.function_definitions in
    let decl, _ = Functions.decl_by_index ctxt.function_context idx in
    assert (String.equal decl.Function_declaration.name unt_func.F.name) ;
    decl
  in
  let%bind expr =
    spanned_bind (type_expression decl ctxt.function_context unt_func.F.expr)
  in
  let%bind expr_ty = type_of_expr ctxt decl expr in
  if Type.equal expr_ty decl.Function_declaration.ret_ty then
    return {ctxt with function_definitions= expr :: ctxt.function_definitions}
  else
    return_err
      (Error.Return_type_mismatch
         {expected= decl.Function_declaration.ret_ty; found= expr_ty})


let make unt_ast =
  let module U = Untyped_ast in
  let rec add_aliases ast = function
    | unt_type :: types ->
        let%bind new_ast = add_alias ast unt_type in
        add_aliases new_ast types
    | [] -> return ast
  in
  let rec add_function_declarations ast = function
    | unt_func :: funcs ->
        let%bind new_ast = add_function_declaration ast unt_func in
        add_function_declarations new_ast funcs
    | [] -> return ast
  in
  let rec add_function_definitions ast = function
    | unt_func :: funcs ->
        let%bind new_ast = add_function_definition ast unt_func in
        add_function_definitions new_ast funcs
    | [] -> return ast
  in
  let ret =
    {type_context= []; function_context= []; function_definitions= []}
  in
  let%bind ret = add_aliases ret unt_ast.U.aliases in
  let%bind ret = add_function_declarations ret unt_ast.U.funcs in
  add_function_definitions ret unt_ast.U.funcs
