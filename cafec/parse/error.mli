open Cafec_spanned.Prelude

type expected_token =
  | Expected_specific of Token.t
  | Expected_item_declarator
  | Expected_identifier_or_under
  | Expected_identifier
  | Expected_expression
  | Expected_expression_follow

type t =
  | Unclosed_comment
  | Malformed_number_literal
  | Reserved_token of string
  | Unrecognized_character of char
  | Unexpected_token of (expected_token * Token.t)

module Monad_spanned : module type of Cafec_spanned.Monad (struct
  type nonrec t = t end)

val print : t -> unit

val print_spanned : t spanned -> unit
