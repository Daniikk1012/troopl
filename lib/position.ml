type t = { offset : int; line : int; column : int }

let zero = { offset = 0; line = 1; column = 1 }

let next u pos =
  if u = Uchar.of_char '\n' then
    { offset = pos.offset + 1; line = pos.line + 1; column = 1 }
  else {
    pos with
    offset = pos.offset + Uchar.utf_8_byte_length u;
    column = pos.column + 1;
  }

let to_string pos = string_of_int pos.line ^ ":" ^ string_of_int pos.column
