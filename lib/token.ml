type kind =
  | OpenParen
  | CloseParen
  | OpenObject
  | CloseObject
  | OpenBlock
  | CloseBlock
  | Number of float
  | String of string
  | Variable of string
  | Method of string
  | Eof

type t = { kind : kind; pos : Position.t }

let string_of_kind = function
  | OpenParen -> "OpenParen"
  | CloseParen -> "CloseParen"
  | OpenObject -> "OpenObject"
  | CloseObject -> "CloseObject"
  | OpenBlock -> "OpenBlock"
  | CloseBlock -> "CloseBlock"
  | Number x -> "Number " ^ string_of_float x
  | String s -> "String \"" ^ String.escaped s ^ "\""
  | Variable v -> "Variable " ^ v
  | Method m -> "Method " ^ m
  | Eof -> "Eof"

let to_string token =
  Position.to_string token.pos ^ ": " ^ string_of_kind token.kind

(* User-facing spelling for diagnostics; [string_of_kind] stays for dumps. *)
let describe = function
  | OpenParen -> "'('"
  | CloseParen -> "')'"
  | OpenObject -> "'{'"
  | CloseObject -> "'}'"
  | OpenBlock -> "'['"
  | CloseBlock -> "']'"
  | Number x -> "number " ^ Number_format.string_of_number x
  | String _ -> "string literal"
  | Variable v -> "variable " ^ v
  | Method m -> "method " ^ m
  | Eof -> "end of file"
