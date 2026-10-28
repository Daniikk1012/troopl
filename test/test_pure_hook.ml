open Troopl
let env = Env.make ()
let eval source =
  let ir = Lexer.create source |> Parser.parse |> Lowerer.lower in
  Evaluator.eval ir.scope_size env ir.ir
let call obj name args =
  Value.get_method obj name (List.length args) env args
let hook source =
  let e = eval ("C (core) X (C extend) R 42 B (box R) " ^
    "E {() core {C extend {X number N " ^ source ^ "}}} {e (E) b (B)}") in
  let host = call e "e" [] in
  let extension = call (call host "core" []) "extend" [] in
  host, call e "b" [], Value.get_method extension "number" 1
let () =
  let input = Builtins.make_number env 1. in
  let host, _, identity = hook "(N)" in
  assert (identity host [input] == input);
  let host, _, constant = hook "(R)" in
  assert (constant host [input] == constant host [input]);
  let host, _, decorate = hook "{N extra 0}" in
  assert (decorate host [input] != decorate host [input]);
  let host, box, mutate = hook "((B set N) N)" in
  let other = Builtins.make_number env 2. in
  ignore (mutate host [input]);
  ignore (mutate host [other]);
  assert (call box "get" [] == other);
  let host, box, read = hook "(B get)" in
  ignore (call box "set" [input]);
  assert (read host [other] == input);
  ignore (call box "set" [other]);
  assert (read host [input] == other);
  assert (Pure_hook.prove (Selector.intern "number" 1) [Some 0]
    (Ir.Variable 0) = Pure_hook.Argument 0);
  assert (Pure_hook.prove (Selector.intern "other" 1) [Some 0]
    (Ir.Variable 0) = Pure_hook.Unknown);
  print_endline "8 pure-hook prototype checks passed"
