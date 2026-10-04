open Troopl

let () =
  (Lexer.create "C 1 B 2 {a A B (A + C)}" |> Parser.parse |> Lowerer.lower).ir
  |> Ir.to_string |> print_endline
