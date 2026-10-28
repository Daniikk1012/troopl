open Troopl
let lower s = Lexer.create s |> Parser.parse |> Lowerer.lower
let eval env s =
  let ir = lower s in Evaluator.eval ir.scope_size env ir.ir
let measure label env =
  let samples = List.init 5 (fun _ ->
    Gc.full_major ();
    let before = Gc.allocated_bytes () in
    let start = Unix.gettimeofday () in
    for i = 1 to 100000 do
      ignore (Sys.opaque_identity (Builtins.make_number env (float i)))
    done;
    Unix.gettimeofday () -. start, Gc.allocated_bytes () -. before)
    |> List.sort compare in
  let seconds, bytes = List.nth samples 2 in
  Printf.printf "%s,100000,%.6f,%.0f\n%!" label seconds bytes
let () =
  let base = Env.make () in
  let prefix = "C (core) X (C extend) " in
  List.iter (fun (label, body) ->
    let env = eval base (prefix ^
      "R 42 E {() core {C extend {X number N " ^ body ^ "}}} E") in
    ignore (Builtins.make_number env 0.);
    measure label env)
    ["pure-identity", "(N)"; "pure-constant", "(R)";
     "fresh-decoration-fallback", "{N extra 0}"]
