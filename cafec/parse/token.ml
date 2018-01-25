open Cafec_spanned.Prelude

module Prelude = struct
  type keyword =
  | Keyword_true
  | Keyword_false
  | Keyword_if
  | Keyword_else
  | Keyword_let
  | Keyword_underscore

  type t =
  | Open_paren
  | Close_paren
  | Open_brace
  | Close_brace
  | Keyword of keyword
  | Identifier of string
  | Operator of string
  | Integer_literal of int
  | Arrow
  | Colon
  | Equals
  | Semicolon
  | Comma
  | Eof
end

include Prelude

let print_keyword = function
| Keyword_true -> print_string "true"
| Keyword_false -> print_string "false"
| Keyword_if -> print_string "if"
| Keyword_else -> print_string "else"
| Keyword_let -> print_string "let"
| Keyword_underscore -> print_char '_'

let print = function
| Open_paren -> print_string "open paren `(`"
| Close_paren -> print_string "close paren `)`"
| Open_brace -> print_string "open brace `{`"
| Close_brace -> print_string "close brace `}`"
| Keyword kw ->
  print_string "keyword: ";
  print_keyword kw
| Operator op ->
  print_string "operator: ";
  print_string op
| Identifier id ->
  print_string "identifier: ";
  print_string id
| Integer_literal i ->
  print_string "int literal: ";
  print_int i
| Arrow -> print_string "arrow `->`"
| Colon -> print_string "colon `:`"
| Equals -> print_string "equals `=`"
| Semicolon -> print_string "semicolon `;`"
| Comma -> print_string "comma `,`"
| Eof -> print_string "end of file"

let print_spanned (tok, sp) =
  print tok;
  Printf.printf
    " from (%d, %d) to (%d, %d)"
    sp.start_line
    sp.start_column
    sp.end_line
    sp.end_column