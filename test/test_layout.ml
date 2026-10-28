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
  let selector = Selector.intern "payload" 0 in
  let layout = Value.create_number_layout [|
    selector, (fun captured env _ -> Builtins.make_number env captured)
  |] in
  let a = Value.number_from_layout layout 1.
  and b = Value.number_from_layout layout 2. in
  assert (Value.as_number (call a "payload" []) = 1.);
  assert (Value.as_number (call b "payload" []) = 2.);
  let duplicate = try
    ignore (Value.create_number_layout [|
      selector, (fun _ _ _ -> Value.empty ());
      selector, (fun _ _ _ -> Value.empty ())
    |]); false with Invalid_argument _ -> true in
  assert duplicate;
  print_endline "8 shared-layout prototype checks passed"
