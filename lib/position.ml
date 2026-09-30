type t = { offset : int; line : int; column : int }

let zero = { offset = 0; line = 1; column = 1 }

let next c pos =
  if c == '\n' then
    { offset = pos.offset + 1; line = pos.line + 1; column = 1 }
  else { pos with offset = pos.offset + 1; column = pos.column + 1 }

let to_string pos = string_of_int pos.line ^ ":" ^ string_of_int pos.column
