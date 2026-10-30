open Troopl

let eval env source =
  let ir = Lexer.create source |> Parser.parse |> Lowerer.lower in
  Evaluator.eval ir.scope_size env ir.ir
let call env object_ name args =
  Value.get_method object_ name (List.length args) env args
let read path = In_channel.with_open_bin path In_channel.input_all
let base = Env.make ()
let measure name units operation =
  ignore (operation ());
  let samples = List.init 5 (fun _ ->
    Gc.full_major ();
    let before = Gc.allocated_bytes () and start = Unix.gettimeofday () in
    let result = operation () in
    let elapsed = Unix.gettimeofday () -. start in
    let bytes = Gc.allocated_bytes () -. before in
    ignore (Sys.opaque_identity result);
    elapsed, bytes) |> List.sort compare in
  let seconds, bytes = List.nth samples 2 in
  Printf.printf "%s,%d,%.6f,%.2f\n%!" name units seconds (bytes /. float units)
let repeat count operation () =
  let last = ref (Value.empty ()) in
  for i = 1 to count do last := operation i done;
  !last
let retained name count operation =
  Gc.full_major ();
  let before = (Gc.stat ()).live_words in
  let held = Array.init count operation in
  Gc.full_major ();
  let after = (Gc.stat ()).live_words in
  Printf.printf "%s,%d,%.2f\n%!" name count
    (float ((after - before) * (Sys.word_size / 8)) /. float count);
  ignore (Sys.opaque_identity held)

let () =
  let library = eval base (read "stdlib/stdlib.tr") in
  let std = call base library "extend" [base] in
  let factory = eval base "N 1 F {run {N}} F" in
  let include_number = Value.get_method factory "run" 0 in
  let number = Builtins.make_number base 1. in
  if Array.length Sys.argv = 2 && Sys.argv.(1) = "--retained" then (
    print_endline "workload,retained_objects,live_bytes_per_object_including_array_slot";
    retained "native-number" 10000 (fun i -> Builtins.make_number base (float i));
    retained "stdlib-number" 10000 (fun i -> Builtins.make_number std (float i));
    retained "include-existing-number" 10000 (fun _ -> include_number base []);
    retained "bind-existing-number" 10000 (fun _ -> Value.bind base number))
  else (
    print_endline "workload,units,median_seconds,allocated_bytes_per_unit";
    let layered = eval base
      "C (core) X (C extend) E {() core {C extend {X number N {{N first 1} second 2}}}} E" in
    List.iter (fun (label, env) ->
      measure label 20000 (repeat 20000 (fun i ->
        Builtins.make_number env (float i))))
      ["construct-native", base; "construct-stdlib", std;
       "construct-two-inclusions", layered];
    measure "include-existing-number" 50000
      (repeat 50000 (fun _ -> include_number base []));
    let factory = eval base
      "N 1 F {run {a (N) b (N) c (N) d (N) e (N) f (N) g (N) h (N)}} F" in
    let run = Value.get_method factory "run" 0 in
    measure "construct-eight-guest-methods" 50000
      (repeat 50000 (fun _ -> run base []));
    let selector = Selector.intern "-" 0 in
    measure "embedding-numeric-lookup" 1000000 (fun () ->
      let last = ref (Value.get_method_id number selector) in
      for _ = 1 to 1000000 do last := Value.get_method_id number selector done;
      ignore (Sys.opaque_identity last);
      number);
    measure "bind-existing-number" 20000
      (repeat 20000 (fun _ -> Value.bind base number));
    let calculator = eval std (read "examples/calculator/calculator.tr") in
    let source = Builtins.make_string std "2 + 3 * 4" in
    measure "calculator-with-stdlib" 1000 (fun () ->
      let session = call std calculator "new" [] in
      let calculate = Value.get_method session "calculate" 1 in
      let result = ref (Value.empty ()) in
      for _ = 1 to 1000 do result := calculate std [source] done;
      assert (Value.as_number (call std !result "value" []) = 14.);
      !result))
