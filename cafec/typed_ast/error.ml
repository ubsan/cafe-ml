module Spanned = Cafec_spanned

type t =
  | Name_not_found of string
  | Type_not_found of Cafec_parse.Ast.Type.builder
  | Call_of_non_function of Type.t
  | Defined_multiple_times of 
    { name: string
    ; original_declaration: Spanned.span }
  | Return_type_mismatch of {expected: Type.t; found: Type.t}
  | Invalid_function_arguments of {expected: Type.t list; found: Type.t list}

module Monad_spanned = Spanned.Monad (struct
  type nonrec t = t
end)

let print = function
  | Name_not_found name -> Printf.printf "Name not found: %s" name
  | Type_not_found ty ->
      print_string "Type not found: " ;
      Cafec_parse.Ast.Type.print ty
  | Call_of_non_function ty ->
      print_string "Attempted to call a non-function type: " ;
      Type.print ty
  | Defined_multiple_times {name; original_declaration} ->
      Printf.printf "Defined %s multiple times.\n" name ;
      print_string "  (original definition at " ;
      Spanned.print_span original_declaration ;
      print_char ')'
  | Return_type_mismatch {expected; found} ->
      print_string "Return value did not match the return type.\n" ;
      print_string "  expected: " ;
      Type.print expected ;
      print_string ", found: " ;
      Type.print found
  | Invalid_function_arguments {expected; found} ->
      print_string "Function arguments did not match the parameter types.\n" ;
      print_string "  expected: " ;
      Type.print_list expected ;
      print_string ", found: " ;
      Type.print_list found


let print_spanned (e, sp) =
  print e ; print_string "\n  at " ; Spanned.print_span sp
