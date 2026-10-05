open Troopl

let () =
  let lowered =
    Lexer.create "L {i N (N < 100000 then-else [L i (N + 1)] [N] run)} L i 0"
    |> Parser.parse |> Lowerer.lower
  in
  let env = Value.uninitialized () in
  Value.initialize env;
  Evaluator.eval lowered.scope_size env lowered.ir |> Value.to_string
  |> print_endline
