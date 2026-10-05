open Troopl

let eval env string =
  let lowered = Lexer.create string |> Parser.parse |> Lowerer.lower in
  Evaluator.eval lowered.scope_size env lowered.ir

let check_number string number =
  Value.as_number (eval Env.default string) = number

let errors string =
  try ignore (eval Env.default string); false with Runtime.Error _ -> true

let () = assert (check_number "A 1 B 2 A + B"                  3.)
let () = assert (check_number "A {1 a (A)} A a"                1.)
let () = assert (check_number "1 2"                            2.)
let () = assert (check_number "A 1 B A C B"                    1.)
let () = assert (check_number "1 + 2 * 3"                      9.)
let () = assert (check_number "1 < 2 then-else 3 4"            3.)
let () = assert (check_number "1 > 2 then-else 3 4"            4.)
let () = assert (check_number "S \"012\" S at 0 + (S at 1)"   97.)
let () = assert (check_number "S \"012\" S size"               3.)
let () = assert (check_number "S \"я\" S at 0"              1103.)
let () = assert (check_number "S \"я\" S size"                 1.)

let () =
  let string = "L {i N (N < 100000 then-else [L i (N + 1)] [N] run)} L i 0" in
  assert (check_number string 100000.)

let () =
  let env = Value.uninitialized () in
  Value.add_methods env Env.default;
  Value.add_method env "inc" 1 (fun env values ->
    (List.hd values |> Value.as_number) +. 1. |> Builtins.make_number env);
  Value.initialize env;
  assert (Value.as_number (eval env "inc 3") = 4.)

let () = assert (errors "S {S}")
let () = assert (errors "S {m 1 (S m)}")
let () = assert (errors "S {1 (1 + S)}")
let () = assert (errors "S {} S m")
let () = assert (errors "S {} 1 + S")

let () = print_endline "test_evaluator successful"
