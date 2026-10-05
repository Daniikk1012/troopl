open Troopl

let () =
  let lowered =
    Lexer.create "E () (env run {E core {(E core) extend {(E core extend) number N {N asdf 0}}}} [1])"
    |> Parser.parse |> Lowerer.lower
  in
  Evaluator.eval lowered.scope_size Env.default lowered.ir |> Value.to_string
  |> print_endline
