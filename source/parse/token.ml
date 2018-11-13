include Types.Token

let equal lhs rhs =
  match (lhs, rhs) with
  | Open_paren, Open_paren -> true
  | Close_paren, Close_paren -> true
  | Open_brace, Open_brace -> true
  | Close_brace, Close_brace -> true
  | Open_square, Open_square -> true
  | Close_square, Close_square -> true
  | Semicolon, Semicolon -> true
  | Dot, Dot -> true
  | Comma, Comma -> true
  | Integer_literal i1, Integer_literal i2 -> i1 = i2
  | Assign, Assign -> true
  | Arrow, Arrow -> true
  | Equals, Equals -> true
  | Colon, Colon -> true
  | Double_colon, Double_colon -> true
  | Operator id1, Operator id2 -> Ident.equal id1 id2
  | Identifier id1, Identifier id2 -> Ident.equal id1 id2
  | Keyword_true, Keyword_true -> true
  | Keyword_false, Keyword_false -> true
  | Keyword_if, Keyword_if -> true
  | Keyword_else, Keyword_else -> true
  | Keyword_func, Keyword_func -> true
  | Keyword_type, Keyword_type -> true
  | Keyword_data, Keyword_data -> true
  | Keyword_record, Keyword_record -> true
  | Keyword_alias, Keyword_alias -> true
  | Keyword_let, Keyword_let -> true
  | Keyword_mut, Keyword_mut -> true
  | Keyword_underscore, Keyword_underscore -> true
  | Eof, Eof -> true
  | _ -> false

let to_string = function
  | Open_paren -> "open paren `(`"
  | Close_paren -> "close paren `)`"
  | Open_brace -> "open brace `{`"
  | Close_brace -> "close brace `}`"
  | Open_square -> "open square `[`"
  | Close_square -> "close square `]`"
  | Semicolon -> "semicolon `;`"
  | Dot -> "dot `.`"
  | Comma -> "comma `,`"
  | Integer_literal i -> Printf.sprintf "int literal: `%d`" i
  | Assign -> "assign `<-`"
  | Arrow -> "arrow `->`"
  | Equals -> "equals `=`"
  | Colon -> "colon `:`"
  | Double_colon -> "double colon `::`"
  | Operator ident -> Printf.sprintf "operator: `%s`" (ident :> string)
  | Identifier ident -> Printf.sprintf "identifier: `%s`" (ident :> string)
  | Keyword_true -> "true"
  | Keyword_false -> "false"
  | Keyword_if -> "if"
  | Keyword_else -> "else"
  | Keyword_func -> "func"
  | Keyword_type -> "type"
  | Keyword_data -> "data"
  | Keyword_record -> "record"
  | Keyword_alias -> "alias"
  | Keyword_let -> "let"
  | Keyword_mut -> "mut"
  | Keyword_underscore -> "_"
  | Eof -> "end of file"
