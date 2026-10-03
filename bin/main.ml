open Troopl

let () =
  Lexer.create "A B C" |> Parser.parse
  |> Expression.to_string |> print_endline
