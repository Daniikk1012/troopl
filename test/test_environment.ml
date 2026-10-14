open Troopl

let checks = ref 0
let check label condition =
  incr checks;
  if not condition then failwith label

let eval ?(env = (Env.make ())) ?(filename = "test.tr") source =
  let lowered =
    Lexer.create ~filename source |> Parser.parse |> Lowerer.lower
  in
  Evaluator.eval lowered.scope_size env lowered.ir

let call env value name args =
  Value.get_method value name (List.length args) env args
let number = Value.as_number
let string env value = Builtins.string_of_value env value
let choose env value =
  let yes = Value.empty () and no = Value.empty () in
  call env value "then-else" [yes; no] == yes
let ok env value = choose env (call env value "ok?" [])
let n env value = Builtins.make_number env (float value)
let s env value = Builtins.make_string env value
let bytes env values =
  Array.of_list (List.map (n env) values) |> Builtins.make_list env
let at env value i = call env value "at" [n env i]
let size env value = call env value "size" [] |> Builtins.int_of_value
let expect_number source expected =
  check source (number (eval source) = expected)
let expect_error ?(env = (Env.make ())) source filename line column =
  try ignore (eval ~env source); failwith ("expected error: " ^ source)
  with Runtime.Error (_, pos) ->
    check "error filename" (pos.filename = Some filename);
    check "error line" (pos.line = line);
    check "error column" (pos.column = column)

let with_file f =
  let path = Filename.temp_file "troopl-env-" ".bin" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () -> f path)

let () =
  let env = (Env.make ()) in
  let core = call env env "core" [] in
  let extension = call env core "extend" [] in
  List.iter (fun kind ->
    let value = Value.empty () in
    check ("identity " ^ kind)
      (call env extension kind [value] == value))
    ["boolean"; "number"; "string"; "list"];
  let tag = call env core "tag" [n env 17] in
  check "initialized numeric tag" (number tag = 17.);
  check "tag has no methods"
    (try ignore (call env tag "+" [n env 1]); false
     with Runtime.Error _ -> true);
  expect_number "12 -" (-12.);
  expect_number "7- mod 3-" 2.;
  expect_number "1 mod 100000000000000000000" 1.;
  expect_number "2.8 floor" 2.;
  expect_number "2.2 ceil" 3.;
  expect_number "2.8- trunc" (-2.);
  List.iter (fun name ->
    try ignore (eval ("0 " ^ name ^ " 2"));
        failwith "rounding accepted an argument"
    with Runtime.Error _ -> ()) ["floor"; "ceil"; "trunc"];
  List.iter (fun value ->
    let source = Builtins.string_of_number value in
    check ("numeric spelling " ^ source) (number (eval source) = value))
    [1e20; 1e-20; -1e20; 0.; 0.1; 123456789012345.];
  expect_number "B (box 0) B set 7 get" 7.;
  expect_number "A (array push 1) A set 0 7 at 0" 7.;
  expect_number "A (array push 1 push 2) (A pop) A size" 1.;
  expect_number
    "N 1 Base (core) Ext (Base extend) E {() core {Base extend {Ext number X {X extra 9}}}} (env run E [N + 1 extra])"
    9.;
  expect_number
    "C (core) X (C extend) E {() core {C extend {X list L {L marker 99}}}} (env run E [(utf-8 from-string \"A\") marker])"
    99.;
  expect_number
    "C (core) X (C extend) E {() core {C extend {X list L {L marker 99}}}} (env run E [(utf-8 to-string (utf-8 from-string \"A\")) remainder marker])"
    99.;
  let list = call env core "from-seq" [eval
    "S {run {cons? {then-else A B (A)} get 7 next {run {cons? {then-else A B (B)}}}}} S"] in
  check "sequence custom Church booleans" (size env list = 1);
  check "sequence get" (number (at env list 0) = 7.);
  check "list at stable identity" (at env list 0 == at env list 0);
  check "list size stable identity"
    (call env list "size" [] == call env list "size" []);
  let empty = call env core "from-seq" [eval "{run {cons? (false)}}"] in
  check "nil does not need get/next" (size env empty = 0);
  let large = eval
    "S {from I {run (I < 100000 then-else [{cons? (true) get (I) next (S from (I + 1))}] [{cons? (false)}] run)}} () core from-seq (S from 0)" in
  check "100000 sequence nodes" (size env large = 100000);
  check "sequence last element" (number (at env large 99999) = 99999.);
  expect_number
    "L {run I (I < 1000000 then-else [L run (I + 1)] [I] run)} L run 0"
    1000000.;
  let utf8 = call env env "utf-8" [] in
  let original = s env "Hello я🙂\r\n" in
  let encoded = call env utf8 "from-string" [original] in
  let decoded = call env utf8 "to-string" [encoded] in
  check "UTF-8 success" (ok env decoded);
  check "UTF-8 roundtrip" (string env decoded = "Hello я🙂\r\n");
  check "UTF-8 remainder empty"
    (size env (call env decoded "remainder" []) = 0);
  List.iter (fun values ->
    let partial = call env utf8 "to-string" [bytes env values] in
    check "incomplete is successful" (ok env partial);
    check "complete prefix only" (string env partial = "A");
    check "incomplete suffix retained"
      (size env (call env partial "remainder" []) = List.length values - 1))
    [[65; 0xc2]; [65; 0xe2; 0x82]; [65; 0xf0; 0x9f; 0x99]];
  List.iter (fun (values, index, byte) ->
    let result = call env utf8 "to-string" [bytes env values] in
    check "invalid UTF-8 failure" (not (ok env result));
    check "invalid byte index"
      (number (call env result "index" []) = float index);
    check "invalid byte value"
      (number (call env result "byte" []) = float byte);
    check "failure has message" (String.length
      (string env (call env result "message" [])) > 0);
    check "failure has no string size"
      (try ignore (call env result "size" []); false
       with Runtime.Error _ -> true))
    [([0x80], 0, 0x80); ([0xc0; 0x80], 0, 0xc0);
     ([0xe0; 0x80], 1, 0x80); ([0xed; 0xa0; 0x80], 1, 0xa0);
     ([0xf4; 0x90; 0x80; 0x80], 1, 0x90);
     ([65; 0xe2; 40; 0xa1], 2, 40); ([256], 0, 256)];
  let array = eval "(array push 65 push 226 push 130)" in
  let partial = call env utf8 "to-string" [array] in
  let suffix = call env partial "remainder" [] in
  ignore (call env array "set" [n env 1; n env 240]);
  check "remainder delegates without copying" (number (at env suffix 0) = 240.);
  let fs = call env env "fs" [] in
  with_file (fun path ->
    let path_value = s env path in
    let result = call env fs "write" [path_value; encoded] in
    check "whole-file write" (ok env result);
    let result = call env fs "read" [path_value] in
    check "whole-file read" (ok env result);
    check "binary bytes preserved"
      (Builtins.bytes_of_value env result = Builtins.bytes_of_value env encoded);
    let reader = call env fs "open-read" [path_value] in
    check "open-read success" (ok env reader);
    check "read at most N" (size env (call env reader "read" [n env 1]) = 1);
    check "read zero" (size env (call env reader "read" [n env 0]) = 0);
    ignore (call env reader "read" [n env 999]);
    let eof = call env reader "read" [n env 10] in
    check "EOF is empty successful list" (ok env eof && size env eof = 0);
    check "close succeeds" (ok env (call env reader "close" []));
    check "read after close fails"
      (not (ok env (call env reader "read" [n env 1])));
    check "double close fails" (not (ok env (call env reader "close" [])));
    let writer = call env fs "open-write" [path_value] in
    check "open-write success" (ok env writer);
    let result = call env writer "write" [bytes env [0; 13; 10; 255]] in
    check "stream write result can close" (ok env (call env result "close" []));
    check "write after close fails"
      (not (ok env (call env writer "write" [bytes env [0]])));
    check "invalid write path is recoverable"
      (not (ok env (call env fs "open-write" [s env (path ^ "/child")])));
    let result = call env fs "read" [path_value] in
    check "binary stream preserves NUL/CR/LF/255"
      (Builtins.bytes_of_value env result = Bytes.of_string "\000\r\n\255");
    let missing = s env (path ^ ".missing") in
    let failed = call env fs "read" [missing] in
    check "OS read failure is a value" (not (ok env failed));
    check "read failure has no at"
      (try ignore (call env failed "at" [n env 0]); false
       with Runtime.Error _ -> true);
    (try ignore (call env fs "write" [path_value; bytes env [256]]);
         failwith "invalid byte did not crash"
     with Runtime.Error _ -> ());
    check "invalid write did not truncate file"
      (In_channel.with_open_bin path In_channel.input_all = "\000\r\n\255"));
  with_file (fun input_path ->
    with_file (fun output_path ->
      with_file (fun error_path ->
        Out_channel.with_open_bin input_path (fun c ->
          output_string c "я🙂\r\n");
        In_channel.with_open_bin input_path (fun input ->
          Out_channel.with_open_bin output_path (fun output ->
            Out_channel.with_open_bin error_path (fun error ->
              let env = Env.make ~input ~output ~error () in
              let io = call env env "io" [] in
              let line = call env io "read-line" [] in
              check "read-line success" (ok env line);
              check "LF stripped, CR retained" (string env line = "я🙂\r");
              check "input EOF failure"
                (not (ok env (call env io "read-line" [])));
              let result = call env io "print" [s env "hello"] in
              check "IO success wrapper" (ok env result);
              ignore (call env result "raw-print" [s env "raw"]);
              let err = call env io "error" [] in
              check "stderr print success"
                (ok env (call env err "print" [s env "error"]));
              ignore (call env err "raw-print" [s env "tail"]);
              flush output;
              flush error;
              check "stdout exact bytes"
                (In_channel.with_open_bin output_path In_channel.input_all
                 = "hello\nraw");
              check "stderr exact bytes"
                (In_channel.with_open_bin error_path In_channel.input_all
                 = "error\ntail")))))));
  expect_error "\n\"abc\" at 99" "<string>" 2 7;
  expect_error "\n{} missing" "<string>" 2 4;
  expect_error "S {\n  S\n}" "<string>" 2 3;
  expect_error "E {() filename \"virtual.tr\"}\n(env run E [\n  1 + {}\n])"
    "virtual.tr" 3 5;
  expect_error ~env:(eval "C (core) {core (C)}")
    "\n{} missing" "test.tr" 2 4;
  expect_error ~env:(eval "{() filename {}}")
    "\n{} missing" "test.tr" 2 4;
  expect_error ~env:(eval "F \"virtual.tr\" {filename (F)}")
    "\n1" "test.tr" 2 1;
  expect_error
    "C (core) Ext (C extend) F \"virtual.tr\" E {() core {C extend {Ext number N {N marker (N)}}} filename {size (F size) at I (F at (I marker))}} (env run E [{} missing])"
    "virtual.tr" 1 156;
  expect_error "\n(io print {size {} at I 65})" "<string>" 2 5;
  expect_error "\n(io print {size 1 at I ({} nope)})" "<string>" 2 28;
  expect_error "\n(crash \"boom\")" "<string>" 2 2;
  (try ignore (eval "S {(S missing (crash \"argument ran\"))}");
       failwith "uninitialized receiver did not fail"
   with Runtime.Error (message, _) ->
     check "uninitialized receiver checked before arguments"
       (message = "attempt to call a method on an uninitialized object"));
  (try ignore (eval ~filename:"nested.tr" "(eval \"Missing\")");
       failwith "eval should fail lowering"
   with Lowerer.Error (_, pos) ->
     check "eval compile filename" (pos.filename = Some "<string>"));
  (try ignore (Lexer.create ~filename:"bad.tr" "#\255" |> Lexer.next_token);
       failwith "invalid UTF-8 comment should fail"
   with Lexer.Error (_, pos) ->
     check "UTF-8 source location"
       (pos.filename = Some "bad.tr" && pos.column = 2));
  (try ignore (Builtins.make_string env "\255");
       failwith "invalid native string should fail"
   with Invalid_argument _ -> ());
  (try ignore (Evaluator.eval 1 env (Ir.Variable 0));
       failwith "uninitialized slot should fail"
   with Invalid_argument _ -> ());
  let pos = Position.next '\n' Position.zero in
  check "number IR prints position"
    (Ir.to_string (Ir.Number (1., pos)) = "Number 1. at 2:1");
  check "string IR prints position"
    (Ir.to_string (Ir.String ("x", pos)) = "String \"x\" at 2:1");
  check "context does not leak after failure"
    (number (eval "17") = 17.);
  Printf.printf "%d environment/diagnostic checks passed\n%!" !checks
