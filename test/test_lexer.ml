open Troopl

let test string list =
  let lexer = Lexer.create string in
  let rec loop list =
    let token = Lexer.next_token lexer in
    match list with
    | (kind, offset, line, column) :: xs ->
        let token = Option.get token in
        assert (token.kind       = kind);
        assert (token.pos.offset = offset);
        assert (token.pos.line   = line);
        assert (token.pos.column = column);
        loop xs
    | [] -> assert (Lexer.next_token lexer |> Option.is_none)
  in
  loop list

let () =
  test "" [];
  test "()[]{}" [
    (Token.OpenParen,   0, 1, 1);
    (Token.CloseParen,  1, 1, 2);
    (Token.OpenBlock,   2, 1, 3);
    (Token.CloseBlock,  3, 1, 4);
    (Token.OpenObject,  4, 1, 5);
    (Token.CloseObject, 5, 1, 6);
  ];
  test " (\r\n)\t" [(Token.OpenParen, 1, 1, 2); (Token.CloseParen, 4, 2, 1)];
  test "\"\"" [(Token.String "", 0, 1, 1)];
  test "\"abc\"" [(Token.String "abc", 0, 1, 1)];
  test "\"a\"\"b\"\"\" \"\"\"\"" [
    (Token.String "a\"b\"", 0, 1,  1);
    (Token.String "\"",     9, 1, 10);
  ];
  test "Variable method 12.5-" [
    (Token.Variable "Variable",  0, 1,  1);
    (Token.Method   "method",    9, 1, 10);
    (Token.Number   (-12.5),    16, 1, 17);
  ];
  print_endline "test_lexer successful"
