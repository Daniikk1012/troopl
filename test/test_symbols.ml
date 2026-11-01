open Troopl
let env = Experimental.extend (Env.make ())
let eval s =
  let ir = Lexer.create s |> Parser.parse |> Lowerer.lower in
  Evaluator.eval ir.scope_size env ir.ir
let number s n = assert (Value.as_number (eval s) = n)
let fails s =
  assert (try ignore (eval s); false with Runtime.Error _ -> true)
let () =
  number "K (symbol new) O (K new-method 0 [7]) K invoke O (array)" 7.;
  number "K (symbol new) O (symbol new-method K 1 {run X (X)}) () symbol run K 1 O run 8" 8.;
  number "K (symbol new) F {new Name {(K new-method 0 [Name]) other O (K invoke O (array))}} A (F new 7) B (F new 9) A other B" 9.;
  number "K (symbol new) O {(K new-method 0 [1]) (K new-method 0 [2])} K invoke O (array)" 2.;
  number "K (symbol new) O (K new-method 0 [7]) E {() marker 9} B (env bind E O) K invoke B (array)" 7.;
  number "K (symbol new) () symbol equal? K {K} then-else 1 0" 1.;
  number "(symbol equal? (symbol new) (symbol new)) then-else 1 0" 0.;
  fails "K (symbol new) J (symbol new) O (K new-method 0 [7]) J invoke O (array)";
  fails "K (symbol new) O (K new-method 0 [7]) () meta invoke O \"<private>\" (array)";
  fails "symbol equal? {} {}";
  fails "K (symbol new) K new-method 1- []";
  print_endline "11 private-key checks passed"
