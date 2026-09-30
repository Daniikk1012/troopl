open Troopl

let test (pos : Position.t) offset line column string =
  assert (pos.offset = offset);
  assert (pos.line   = line);
  assert (pos.column = column);
  assert (Position.to_string pos = string)

let () =
  let pos = Position.zero in
  test pos 0 1 1 "1:1";
  let pos = Position.next (Uchar.of_char 'a') pos in
  test pos 1 1 2 "1:2";
  let pos = Position.next (Uchar.of_char 'b') pos in
  let pos = Position.next (Uchar.of_char 'c') pos in
  test pos 3 1 4 "1:4";
  let pos = Position.next (Uchar.of_char '\n') pos in
  test pos 4 2 1 "2:1";
  let pos =
    Position.next (String.get_utf_8_uchar "я" 0 |> Uchar.utf_decode_uchar) pos
  in
  test pos 6 2 2 "2:2";
  let pos = Position.next (Uchar.of_char '\n') pos in
  let pos = Position.next (Uchar.of_char '\n') pos in
  test pos 8 4 1 "4:1";
  print_endline "test_position sucessful"
