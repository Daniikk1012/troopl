type t = { offset : int; line : int; column : int }

let zero = { offset = 0; line = 1; column = 1 }

let next c pos =
  if c = '\n' then
    { offset = pos.offset + 1; line = pos.line + 1; column = 1 }
  else {
    pos with
    offset = pos.offset + 1;
    column =
      if int_of_char c land 0xC0 = 0x80 then pos.column else pos.column + 1;
  }

let to_string pos = string_of_int pos.line ^ ":" ^ string_of_int pos.column
