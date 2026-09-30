open Troopl

let test (pos : Position.t) offset line column string =
  assert (pos.offset = offset);
  assert (pos.line   = line);
  assert (pos.column = column);
  assert (Position.to_string pos = string)

let () =
  let pos = Position.zero in
  test pos 0 1 1 "1:1";
  let pos = Position.next 'a' pos in
  test pos 1 1 2 "1:2";
  let pos = Position.next 'b' pos in
  let pos = Position.next 'c' pos in
  test pos 3 1 4 "1:4";
  let pos = Position.next '\n' pos in
  test pos 4 2 1 "2:1";
  let pos = Position.next 'a' pos in
  test pos 5 2 2 "2:2";
  let pos = Position.next '\n' pos in
  let pos = Position.next '\n' pos in
  test pos 7 4 1 "4:1";
  print_endline "test_position sucessful"
