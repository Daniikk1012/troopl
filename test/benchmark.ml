open Troopl

let lower source = Lexer.create source |> Parser.parse |> Lowerer.lower
let run env lowered =
  Evaluator.eval lowered.Lowerer.scope_size env lowered.ir

let measure label units operation =
  (* Warm dispatch and the allocator before timing. Never include parsing. *)
  ignore (operation ());
  let samples = List.init 3 (fun _ ->
    Gc.full_major ();
    let before = Gc.allocated_bytes () in
    let start = Unix.gettimeofday () in
    let result = operation () in
    let elapsed = Unix.gettimeofday () -. start in
    let allocated = Gc.allocated_bytes () -. before in
    Gc.full_major ();
    let stats = Gc.stat () in
    ignore (Sys.opaque_identity result);
    elapsed, allocated, stats.Gc.live_words, stats.Gc.stack_size)
  in
  let samples = List.sort (fun (a, _, _, _) (b, _, _, _) ->
    Float.compare a b) samples in
  let seconds, allocated, live, stack = List.nth samples 1 in
  Printf.printf "%s,%d,%.6f,%.0f,%d,%d\n%!"
    label units seconds allocated live stack

let () =
  let env = Env.make () in
  print_endline "workload,units,median_seconds,allocated_bytes,live_words,stack_words";
  List.iter (fun (label, source) ->
    let ir = lower source in
    measure label 100000 (fun () ->
      let last = ref (Value.empty ()) in
      for _ = 1 to 100000 do last := run env ir done;
      !last))
    ["closures-zero",
      "F {make X (({touch (X)}) {answer 7})} F make 9";
     "closures-inherited",
      "A 1 F {make X ((X) {first {second (A)}})} F make 9"];
  let custom = run env (lower
    "C (core) X (C extend) E {() core {C extend {X number N {N extra 0}}}} E") in
  let ir = lower
    "L {run I (I < 100000 then-else [L run (I + 1)] [I] run)} L run 0" in
  measure "custom-hook-loop" 100000 (fun () -> run custom ir);
  List.iter (fun count ->
    let source = Printf.sprintf
      "L {run I (I < %d then-else [L run (I + 1)] [I] run)} L run 0"
      count in
    let ir = lower source in
    measure "tail-loop" count (fun () -> run env ir))
    [100000; 1000000];
  List.iter (fun count ->
    let source = Printf.sprintf
      "S {from I {run (I < %d then-else [{cons? (true) get (I) next (S from (I + 1))}] [{cons? (false)}] run)}} () core from-seq (S from 0)"
      count in
    let ir = lower source in
    measure "from-seq" count (fun () -> run env ir))
    [10000; 100000];
  let utf8 = Value.get_method env "utf-8" 0 env [] in
  let encode = Value.get_method utf8 "to-bytes" 1 in
  List.iter (fun count ->
    let source = Builtins.make_byte_string env (String.make count 'x') in
    measure "encode-bytes" count (fun () -> encode env [source]))
    [1000; 10000]
