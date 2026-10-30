open Troopl
let env = Experimental.extend (Env.make ())
let eval source =
  let ir = Lexer.create source |> Parser.parse |> Lowerer.lower in
  Evaluator.eval ir.scope_size env ir.ir
let number source n = assert (Value.as_number (eval source) = n)
let fails source =
  assert (try ignore (eval source); false with Runtime.Error _ -> true)
let () =
  number "O (meta new-method \"add\" 2 {run A B (A + B)}) O add 3 4" 7.;
  number "O (meta new-method \"x\" 0 [7]) meta invoke O \"x\" (array)" 7.;
  number "O {x A (A)} meta invoke O \"x\" (array push 8)" 8.;
  number "N 3 O (meta new-method \"x\" 0 [N]) N 9 O x" 3.;
  number "B [1] O {(meta new-method \"x\" 0 B) x 9} O x" 9.;
  number "B {run (marker)} E {() marker 7} S (env bind E B) O (meta new-method \"x\" 0 S) O x" 7.;
  fails "meta new-method \"x\" 1- []";
  fails "meta new-method \"x\" 0.5 []";
  fails "meta new-method \"x\" 1 []";
  fails "meta invoke {} \"missing\" (array)";
  let base = Env.make () in
  assert (try ignore (Value.get_method base "meta" 0); false
    with Runtime.Error _ -> true);
  print_endline "11 meta capability checks passed"
