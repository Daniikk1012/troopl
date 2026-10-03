type kind = OpenParen  | CloseParen
          | OpenObject | CloseObject
          | OpenBlock  | CloseBlock
          | Number   of float
          | String   of string
          | Variable of string
          | Method   of string
          | Eof

type t = { kind : kind; pos : Position.t }

let string_of_kind = function
  | OpenParen   -> "OpenParen"
  | CloseParen  -> "CloseParen"
  | OpenObject  -> "OpenObject"
  | CloseObject -> "CloseObject"
  | OpenBlock   -> "OpenBlock"
  | CloseBlock  -> "CloseBlock"
  | Number x    -> "Number " ^ string_of_float x
  | String s    -> "String \"" ^ String.escaped s ^ "\""
  | Variable v  -> "Variable " ^ v
  | Method m    -> "Method " ^ m
  | Eof         -> "Eof"

let to_string token =
  Position.to_string token.pos ^ ": " ^ string_of_kind token.kind
