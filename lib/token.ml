type kind = OpenParen  | CloseParen
          | OpenBlock  | CloseBlock
          | OpenObject | CloseObject
          | Number   of float
          | String   of string
          | Variable of string
          | Method   of string

type t = { kind : kind; pos : Position.t }

let string_of_kind = function
  | OpenParen   -> "OpenParen"
  | CloseParen  -> "CloseParen"
  | OpenBlock   -> "OpenBlock"
  | CloseBlock  -> "CloseBlock"
  | OpenObject  -> "OpenObject"
  | CloseObject -> "CloseObject"
  | Number x    -> "Number " ^ string_of_float x
  | String s    -> "String \"" ^ String.escaped s ^ "\""
  | Variable v  -> "Variable " ^ v
  | Method m    -> "Method " ^ m

let to_string token =
  Position.to_string token.pos ^ ": " ^ string_of_kind token.kind
