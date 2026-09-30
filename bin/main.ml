open Troopl

let () =
  let lexer = Lexer.create "Asdf asdf \"he\"\"llo\" ( 123.5- ) other (1 + 2)" in
  Lexer.next_token lexer |> Option.get |> Token.to_string |> print_endline;
  Lexer.next_token lexer |> Option.get |> Token.to_string |> print_endline;
  Lexer.next_token lexer |> Option.get |> Token.to_string |> print_endline;
  Lexer.next_token lexer |> Option.get |> Token.to_string |> print_endline;
  Lexer.next_token lexer |> Option.get |> Token.to_string |> print_endline
