open Troopl

let checks = ref 0
let check label condition =
  incr checks;
  if not condition then failwith label

let eval env filename source =
  let lowered =
    Lexer.create ~filename source |> Parser.parse |> Lowerer.lower
  in
  Evaluator.eval lowered.scope_size env lowered.ir
let call env object_ name args =
  Value.get_method object_ name (List.length args) env args
let read path = In_channel.with_open_bin path In_channel.input_all
let n env i = Builtins.make_number env (float i)
let s env text = Builtins.make_string env text
let truth env value =
  let yes = Value.empty () and no = Value.empty () in
  call env value "then-else" [yes; no] == yes

let () =
  let base = Env.make ~filename:"stdlib-test.tr" () in
  let library = eval base "../stdlib/stdlib.tr" (read "../stdlib/stdlib.tr") in
  let env = call base library "extend" [base] in
  let number source expected =
    let result = eval env "stdlib-test.tr" source |> Value.as_number in
    check source (result = expected)
  in
  let text source expected =
    let result = eval env "stdlib-test.tr" source in
    check source (Builtins.string_of_value env result = expected)
  in
  number "(true) not then-else 1 0" 0.;
  number "(false) not then-else 1 0" 1.;
  number "(true) and (false) then-else 1 0" 0.;
  number "(false) or (true) then-else 1 0" 1.;
  number "(true) xor (true) then-else 1 0" 0.;
  number "(true) xor (false) then-else 1 0" 1.;
  number "(false) and-then [(crash \"unselected\")] then-else 1 0" 0.;
  number "(true) or-else [(crash \"unselected\")] then-else 1 0" 1.;
  number "(true) then [42] else [(crash \"unselected\")]" 42.;
  number "(false) then [0] else-if [(true)] [42] else [7]" 42.;
  number "(true) then [42] else-if [(crash \"unselected\")] [0] else [7]" 42.;
  number "(false) then [0] else-if [(false)] [1] else [42]" 42.;
  number "Cell (box 0) ((false) then [Cell set 1] end) Cell get" 0.;
  text "(true) to-string" "true";
  text "(false) to-string" "false";
  number "12- abs" 12.;
  number "7 min 3" 3.;
  number "7 max 3" 7.;
  text "\"Hello\" + \", \" + \"Troopl!\"" "Hello, Troopl!";
  text "\"abcdef\" substring 1 4" "bcd";
  text "\"я🙂\" reverse" "🙂я";
  number "\"same\" equals \"same\" then-else 1 0" 1.;
  number "\"same\" equals \"other\" then-else 1 0" 0.;
  text "\"abcdef\" substring 2 2" "";
  text "\"abc\" reverse strict" "cba";
  number "(list of and 1 and 2 and 3 end) size" 3.;
  number "(list range 10 15) at 3" 13.;
  number "(list range 0 3) map {run X (X * X)} at 2" 4.;
  number "(list range 1 6) fold {run A B (A + B)} 0" 15.;
  number "(list range 0 6) filter {run X (X mod 2 = 0)} size" 3.;
  number "(list range 0 6) filter {run X (X mod 2 = 0)} at 2" 4.;
  number "((list range 0 2) + (list range 2 4)) at 3" 3.;
  number "(list range 0 0) is-empty then-else 1 0" 1.;
  number "Cell (box 0) ((list range 1 4) for-each {run X (Cell set ((Cell get) + X))}) Cell get" 6.;
  number "(list range 0 100000) strict at 99999" 99999.;
  number "Cell (box 0) M ((list range 0 1) map {run X ((Cell set ((Cell get) + 1)) X)}) (M at 0) (M at 0) Cell get" 2.;
  number "A (array push 1) L (list from A) (A set 0 7) L at 0" 1.;
  number "A (array push 1) L (list from-minimal A) (A set 0 7) L at 0" 7.;
  List.iter (fun source ->
    check ("bounds " ^ source)
      (try ignore (eval env "stdlib-test.tr" source); false
       with Runtime.Error _ -> true))
    ["(list range 0 3) at 3"; "\"abc\" substring 0 4";
     "\"abc\" reverse at 3"; "(list range 0 3) at 0.5"];
  let path = Filename.temp_file "troopl-module-" ".tr" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let fs = call env env "fs" [] in
    let filename = s env path in
    let content = s env "{value (answer) filename (filename)}" in
    let written = call env fs "write-text" [filename; content] in
    check "stdlib text write"
      (truth env (call env written "ok?" []));
    let loaded = call env fs "read-text" [filename] in
    check "stdlib text read"
      (Builtins.string_of_value env loaded
       = "{value (answer) filename (filename)}");
    let module_env = eval env "stdlib-test.tr" "{() answer 42}" in
    let module_ = call env env "import" [module_env; filename] in
    let other = eval env "stdlib-test.tr" "{() answer 7}" in
    check "import binds returned methods to module environment"
      (call other module_ "value" [] |> Value.as_number = 42.);
    check "import supplies module filename"
      (call other module_ "filename" [] |> Builtins.string_of_value other
       = path);
    let restricted = eval env "stdlib-test.tr"
      "A 42 C (core) {core (C) answer (A)}" in
    let restricted_module = call env env "import" [restricted; filename] in
    check "module need not expose eval/filesystem capabilities"
      (call env restricted_module "value" [] |> Value.as_number = 42.);
    ignore (call env fs "write-text"
      [filename; s env "{run ({} missing)}"]);
    let bad = call env env "import" [filename] in
    (try ignore (call env bad "run" []); failwith "missing method should fail"
     with Runtime.Error (_, position) ->
       check "imported method reports module filename"
         (position.filename = Some path);
       check "imported method reports method position"
         (position.line = 1 && position.column = 10));
    Out_channel.with_open_bin path (fun c -> output_string c "A\226\130");
    let incomplete = call env fs "read-text" [filename] in
    check "read-text rejects incomplete UTF-8"
      (not (truth env (call env incomplete "ok?" []))));
  Printf.printf "%d standard-library checks passed\n%!" !checks
