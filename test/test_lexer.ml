open Troopl

let test string list =
  let lexer = Lexer.create string in
  let rec loop list =
    let token = Lexer.next_token lexer in
    match list with
    | (kind, offset, line, column) :: xs ->
        assert (token.kind       = kind);
        assert (token.pos.offset = offset);
        assert (token.pos.line   = line);
        assert (token.pos.column = column);
        loop xs
    | [] -> ()
  in
  loop list

let test_fail string =
  let lexer = Lexer.create string in
  let rec loop () =
    match (Lexer.next_token lexer).kind with
    | Eof -> ()
    | _   -> loop ()
  in
  try loop (); assert false
  with Lexer.Error _ -> ()

let () =
  test "" [Eof, 0, 1, 1; Eof, 0, 1, 1; Eof, 0, 1, 1];
  test "()[]{}" [
    OpenParen,   0, 1, 1;
    CloseParen,  1, 1, 2;
    OpenBlock,   2, 1, 3;
    CloseBlock,  3, 1, 4;
    OpenObject,  4, 1, 5;
    CloseObject, 5, 1, 6;
    Eof,         6, 1, 7;
  ];
  test " (\r\n)\t" [OpenParen, 1, 1, 2; CloseParen, 4, 2, 1; Eof, 6, 2, 3];
  test "\"\"" [String "", 0, 1, 1; Eof, 2, 1, 3];
  test "\"abc\"" [String "abc", 0, 1, 1; Eof, 5, 1, 6];
  test "\"a\"\"b\"\"\" \"\"\"\"" [
    String "a\"b\"",  0, 1,  1;
    String "\"",      9, 1, 10;
    Eof,             13, 1, 14;
  ];
  test "Variable method 12.5-" [
    Variable "Variable",  0, 1,  1;
    Method   "method",    9, 1, 10;
    Number   (-12.5),    16, 1, 17;
    Eof,                 21, 1, 22;
  ];
  test "#()[]{}\nabc" [Method "abc", 8, 2, 1; Eof, 11, 2, 4];
  test_fail "\"";
  test_fail "\"abc\"\"";
  test_fail "1a";
  print_endline "test_lexer successful"
