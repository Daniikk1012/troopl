open Troopl

let checks = ref 0
let check label condition =
  incr checks; if not condition then failwith label
let eval env source =
  let lowered = Lexer.create source |> Parser.parse |> Lowerer.lower in
  Evaluator.eval lowered.scope_size env lowered.ir
let call env value name args =
  Value.get_method value name (List.length args) env args
let num = Value.as_number
let n env i = Builtins.make_number env (float i)
let truth env value =
  let yes = Value.empty () and no = Value.empty () in
  call env value "then-else" [yes; no] == yes
let ok env value = truth env (call env value "ok?" [])
let crashes f = try ignore (f ()); false with Runtime.Error _ -> true
let text = Builtins.string_of_value
let with_file f =
  let path = Filename.temp_file "troopl-v02-" ".bin" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () -> f path)

let () =
  let env = Env.make ~arguments:["entry.tr"; "a b"; "\255"] () in
  List.iter (fun (source, expected) ->
    check source (num (eval env source) = expected))
    ["0inf", infinity; "0inf-", neg_infinity; "0inf + 1", infinity];
  check "NaN literal" (Float.is_nan (num (eval env "0nan")));
  List.iter (fun source ->
    check ("reject " ^ source)
      (try ignore (eval env source); false with Lexer.Error _ -> true))
    ["0nan-"; "0infx"; "0Inf"; "1e3"; "1..0"];
  List.iter (fun value ->
    let spelling = Builtins.string_of_number value in
    let result = num (eval env spelling) in
    check ("roundtrip " ^ spelling)
      (if Float.is_nan value then Float.is_nan result
       else Int64.bits_of_float value = Int64.bits_of_float result))
    [nan; infinity; neg_infinity; 0.; -0.; 1e-300; -1e300];
  check "negative zero text" (Builtins.string_of_number (-0.) = "0-");
  check "negative zero divide" (num (eval env "1 / 0-") = neg_infinity);
  check "negative zero negate"
    (not (Float.sign_bit (num (eval env "0- -"))));
  check "negative zero multiply"
    (Float.sign_bit (num (eval env "0- * 2")));
  check "zero comparison"
    (truth env (eval env "0 = 0-"));
  check "NaN comparison" (not (truth env (eval env "0nan = 0nan")));
  check "special literals use extension hook"
    (num (eval env
      "C (core) X (C extend) E {() core {C extend {X number N {N marker 9}}}} (env run E [0inf marker])")
     = 9.);
  let utf8 = call env env "utf-8" [] in
  List.iter (fun name ->
    check ("removed " ^ name)
      (crashes (fun () -> call env utf8 name [Value.empty ()])))
    ["to-string"; "from-string"];
  let minimal = eval env
    "C (core) X (C extend) E {() core {C extend {X list L (crash \"list hook\")}}} (env run E [core from-seq {run {cons? (false)}}])" in
  check "from-seq skips extension"
    (Builtins.size_of_value env minimal = 0);
  check "from-seq only minimal methods" (crashes (fun () ->
    call env minimal "map" []));
  let system = call env env "system" [] in
  let args () = call env system "args" [] in
  let a = args () and b = args () in
  check "args fresh" (a != b);
  check "args size" (Builtins.size_of_value env a = 3);
  List.iteri (fun i expected ->
    check "args bytes" (text env (call env a "at" [n env i]) = expected))
    ["entry.tr"; "a b"; "\255"];
  with_file (fun path ->
    let fs = call env env "fs" [] in
    let filename = Builtins.make_string env path in
    let writer = call env fs "open-write" [filename] in
    let bytes = Builtins.list_of_bytes env (Bytes.of_string "A\000\255") in
    check "file write" (ok env (call env writer "write" [bytes]));
    check "file flush" (ok env (call env writer "flush" []));
    check "flush visible before close"
      (In_channel.with_open_bin path In_channel.input_all = "A\000\255");
    let metadata = call env fs "metadata" [filename] in
    let size = call env metadata "size" [] in
    check "metadata identity" (size == call env metadata "size" []);
    ignore (call env writer "close" []);
    List.iter (fun (name, args) ->
      check ("closed writer " ^ name)
        (crashes (fun () -> call env writer name args)))
      ["write", [bytes]; "flush", []];
    let reader = call env fs "open-read" [filename] in
    ignore (call env reader "close" []);
    check "closed reader crash"
      (crashes (fun () -> call env reader "read" [n env 1]));
    ignore (call env fs "write" [filename; Builtins.make_string env "longer"]);
    check "metadata snapshot" (num size = 3.);
    In_channel.with_open_bin path (fun input ->
      with_file (fun output_path ->
        Out_channel.with_open_bin output_path (fun output ->
          let env = Env.make ~input ~output () in
          let io = call env env "io" [] in
          check "io byte read"
            (Builtins.bytes_of_value env (call env io "read" [n env 2])
             = Bytes.of_string "lo");
          let line = call env io "read-line" [] in
          check "shared input position" (text env line = "nger");
          let eof = call env io "read-line" [] in
          check "EOF error" (not (ok env eof));
          check "EOF flag" (truth env (call env eof "eof?" []));
          check "read EOF empty"
            (Builtins.size_of_value env (call env io "read" [n env 5]) = 0);
          close_in input;
          let failed = call env io "read-line" [] in
          check "IO failure not EOF"
            (not (truth env (call env failed "eof?" [])));
          check "read closed input is recoverable"
            (not (ok env (call env io "read" [n env 5])));
          check "read zero crash"
            (crashes (fun () -> call env io "read" [n env 0]));
          check "raw write" (ok env (call env io "write" [bytes]));
          ignore (call env io "flush" []);
          check "raw output exact"
            (In_channel.with_open_bin output_path In_channel.input_all
             = "A\000\255")))));
  if not Sys.win32 then (
    let child = Filename.concat (Unix.getcwd ()) "process_child.exe" in
    let argv = Builtins.make_list env [|
      Builtins.make_string env child; Builtins.make_string env "signal"
    |] in
    let result = call env system "run" [argv] in
    check "signal completed" (ok env result);
    check "negative native signal"
      (num (call env result "exit-code" []) = -15.));
  Printf.printf "%d Version 0.2 checks passed\n" !checks
