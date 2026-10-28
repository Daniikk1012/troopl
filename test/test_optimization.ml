open Troopl

let checks = ref 0
let check label value = incr checks; if not value then failwith label
let lower source = Lexer.create source |> Parser.parse |> Lowerer.lower
let eval env source =
  let ir = lower source in Evaluator.eval ir.scope_size env ir.ir
let call env obj name args =
  Value.get_method obj name (List.length args) env args
let rec plans ir =
  let entries entries = List.concat_map (function
    | Ir.CompiledMethod m -> (Selector.describe m.selector, m.plan,
        m.scope_size) :: plans m.body
    | Ir.Inclusion i -> plans i.value
    | Ir.Method _ -> []) entries in
  match ir with
  | Ir.Definition d -> plans d.value @ plans d.scope
  | Ir.RecursiveDefinition d -> entries d.entries @ plans d.scope
  | Ir.Object e -> entries e
  | Ir.Sequence (a,b) -> plans a @ plans b
  | Ir.Call c -> plans c.value @ List.concat_map plans c.args
  | _ -> []
let plan name source = List.find (fun (s,_,_) -> s=name)
  (plans (lower source).ir)

let () =
  let a = Selector.intern "same" 0 and b = Selector.intern "same" 1 in
  check "selector stable" (a = Selector.intern ("sa" ^ "me") 0);
  check "arity distinct" (a <> b);
  let ids = Array.make 4 a in
  let threads = Array.init 4 (fun i -> Thread.create (fun () ->
    for _ = 1 to 1000 do ids.(i) <- Selector.intern "parallel" 2 done) ()) in
  Array.iter Thread.join threads;
  check "concurrent selector stable" (Array.for_all ((=) ids.(0)) ids);
  let _, p, locals = plan "inner/0" "A 1 F {outer {inner (A)}}" in
  check "inherited array reuse" (p = Ir.ReuseCaptures);
  check "no capture-copy slots in frame" (locals = 0);
  let _, p, _ = plan "inner/0" "F {outer X {inner (X)}}" in
  check "argument requires gathering"
    (match p with Ir.CaptureValues [|Ir.Local _|] -> true | _ -> false);
  let _, p, _ = plan "answer/0" "{answer 7}" in
  check "zero capture plan" (p = Ir.NoCaptures);
  let env = Env.make () in
  List.iter (fun (source, expected) ->
    check source (Value.as_number (eval env source) = expected))
    ["A 1 F {outer {inner (A)}} F outer inner", 1.;
     "A 1 B 2 F {outer ((A) {inner (B)})} F outer inner", 2.;
     "A 1 F {outer X {inner (A + X)}} F outer 2 inner", 3.;
     "A 1 F {outer {inner (A)}} A 9 F outer inner", 1.;
     "A (box 1) F {outer {inner (A get)}} (A set 9) F outer inner", 9.;
     "F {make X {self (X) again (F make X)}} F make 7 again self", 7.;
     "A 1 B {A (core tag 99)} B + 1", 2.;
     "A 3 F {outer {inner {deep (A)}}} F outer inner deep", 3.;
     "A 1 F {outer X {inner {deep (A + X)}}} F outer 4 inner deep", 5.];
  let weak = Weak.create 1 in
  let host = Value.uninitialized () in
  Value.add_methods host env;
  Value.add_method host "payload" 0 (fun _ _ ->
    let blob = Bytes.make 8388608 'x' in
    Weak.set weak 0 (Some blob);
    let obj = Value.uninitialized () in
    Value.add_method obj "touch" 0 (fun _ _ ->
      ignore (Sys.opaque_identity blob); Value.empty ());
    Value.finish obj);
  Value.initialize host;
  let result = eval host
    "F {make Payload (({read (Payload)}) {answer 7})} F make (payload)" in
  Gc.full_major ();
  check "zero capture releases parent local frame" (not (Weak.check weak 0));
  check "escaping zero-capture method works"
    (Value.as_number (call host result "answer" []) = 7.);
  let inherited = eval host
    "A 7 F {make Payload (({read (Payload)}) {first {answer (A)}})} F make (payload)" in
  Gc.full_major ();
  check "inherited capture releases parent local frame"
    (not (Weak.check weak 0));
  let first = call host inherited "first" [] in
  check "inherited capture survives without parent frame"
    (Value.as_number (call host first "answer" []) = 7.);
  let extension = call env (call env env "core" []) "extend" [] in
  let count = ref 0 in
  let ext = Value.uninitialized () in
  Value.add_methods ext extension;
  Value.add_method ext "number" 1 (fun _ args ->
    incr count; List.hd args);
  Value.initialize ext;
  let core = Value.uninitialized () in
  Value.add_method core "extend" 0 (fun _ _ -> ext);
  Value.initialize core;
  let custom = Value.uninitialized () in
  Value.add_methods custom env;
  Value.add_method custom "core" 0 (fun _ _ -> core);
  Value.initialize custom;
  ignore (eval custom "(1) (1)");
  check "custom hooks never cached" (!count = 2);
  Printf.printf "%d optimization checks passed\n" !checks
