open Troopl
let env = Env.make ()
let call obj name args =
  Value.get_method obj name (List.length args) env args
let eval source =
  let ir = Lexer.create source |> Parser.parse |> Lowerer.lower in
  Evaluator.eval ir.scope_size env ir.ir
let () =
  let cases = [
    "A 1 B {A (core tag 99)} B + 1", 2.;
    "A 1 B {A (core tag 99)} B -", -1.;
    "A 1 B {A (core tag 99) + X 7} B + 100", 7.;
    "A 1 B {A} A 9 B + 1", 2.;
    "A 1 B {A (core tag 99)} E {() marker 7} (env bind E B) + 1", 2.;
  ] in
  List.iter (fun (source,n) -> assert (Value.as_number (eval source) = n))
    cases;
  let a = Builtins.make_number env 1.
  and b = Builtins.make_number env 2. in
  assert (Value.as_number (call a "-" []) = -1.);
  assert (Value.as_number (call b "-" []) = -2.);
  let missing = try ignore (call a "payload" []); false
    with Runtime.Error _ -> true in
  assert missing;
  print_endline "8 shared-layout prototype checks passed"
