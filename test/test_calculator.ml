open Troopl

let () = Printexc.register_printer (function
  | Runtime.Error (message, position) ->
      Some (Position.describe position ^ ": " ^ message)
  | _ -> None)

let checks = ref 0
let check label condition =
  incr checks;
  if not condition then failwith label
let read path = In_channel.with_open_bin path In_channel.input_all
let eval env filename source =
  let lowered = Lexer.create ~filename source |> Parser.parse |> Lowerer.lower in
  Evaluator.eval lowered.scope_size env lowered.ir
let call env value name args =
  Value.get_method value name (List.length args) env args
let truth env value =
  let yes = Value.empty () and no = Value.empty () in
  call env value "then-else" [yes; no] == yes
let ok env value = call env value "ok?" [] |> truth env
let s = Builtins.make_string
let text = Builtins.string_of_value

let contains text needle =
  let rec loop i =
    i + String.length needle <= String.length text
    && (String.sub text i (String.length needle) = needle || loop (i + 1))
  in
  loop 0

let with_file f =
  let path = Filename.temp_file "troopl-calc-" ".txt" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () -> f path)

let () =
  let base = Env.make () in
  let stdlib = eval base "../stdlib/stdlib.tr" (read "../stdlib/stdlib.tr") in
  let env = call base stdlib "extend" [base] in
  let path = "../examples/calculator/calculator.tr" in
  let calculator = eval env path (read path) in
  check "calculator formats conventional negative signs"
    (text env (call env calculator "format" [Builtins.make_number env (-4.)])
     = "-4");
  let session = call env calculator "new" [] in
  let calculate source = call env session "calculate" [s env source] in
  List.iter (fun (source, expected) ->
    let result = calculate source in
    check ("calculator accepts " ^ source) (ok env result);
    check ("calculator value " ^ source)
      (Value.as_number (call env result "value" []) = expected))
    ["2 + 3 * 4", 14.; "(2 + 3) * 4", 20.; "2^3^2", 512.;
     "-2^2", -4.; "(-2)^2", 4.; "2^-3", 0.125; "--2", 2.;
     "10%3", 1.; "-10%3", 2.; "0.5 + 1.25", 1.75;
     "sqrt(81)", 9.; "min(4, 2)", 2.; "max(4, 2)", 4.;
     "pow(2, 5)", 32.; "abs(-7)", 7.; "floor(2.8)", 2.;
     "ceil(2.2)", 3.; "trunc(-2.8)", -2.; "  1 + 2 \t", 3.;
     "radius = 5", 5.; "radius * 2", 10.; "ans + 1", 11.;
     "radius = radius + 1", 6.; "radius", 6.];
  let previous = call env session "previous" [] |> Value.as_number in
  let history_size () = call env session "history" []
    |> fun v -> call env v "size" [] |> Builtins.int_of_value in
  let count = history_size () in
  let spaced = calculate "   ?" in
  check "calculator retains leading-space error position"
    (Value.as_number (call env spaced "column" []) = 4.);
  List.iter (fun source ->
    let result = calculate source in
    check ("calculator rejects " ^ source) (not (ok env result));
    check "calculator error has a message"
      (String.length (text env (call env result "message" [])) > 0);
    check "calculator error has a column"
      (Value.as_number (call env result "column" []) >= 1.);
    check "errors do not update ans"
      (Value.as_number (call env session "previous" []) = previous);
    check "errors do not enter history" (history_size () = count))
    [""; "1 / 0"; "1%0"; "2+"; "(1+2"; "1 2"; "2(3)";
     "unknown"; "sqrt(-1)"; "min(1)"; "pow(1,2,3)"; "1..2";
     "x == 1"; "pi = 3"; "e = 2"; "ans = 7";
     "eval(123)"; "system exit 0"; "0; 1"; ".5"];
  let variables = call env session "variables" [] in
  check "assignments replace existing variable"
    (Value.as_number (call env variables "size" []) = 1.);
  let large = List.init 2000 (fun _ -> "1") |> String.concat "+" in
  let result = calculate large in
  check "long additive chain"
    (ok env result && Value.as_number (call env result "value" []) = 2000.);
  with_file (fun filename ->
    let result = call env session "save" [s env filename] in
    check "session save" (ok env result);
    let restored = call env calculator "new" [] in
    let result = call env restored "load" [s env filename] in
    check "session replay" (ok env result);
    check "session replay count"
      (Value.as_number (call env result "count" []) = float (history_size ()));
    check "session replay preserves ans"
      (Value.as_number (call env restored "previous" []) = 2000.);
    let result = call env restored "calculate" [s env "radius"] in
    check "session replay preserves variables"
      (Value.as_number (call env result "value" []) = 6.);
    Out_channel.with_open_bin filename (fun c ->
      output_string c "x = 1\n2+\n");
    let result = call env restored "load" [s env filename] in
    check "bad session is recoverable" (not (ok env result));
    check "bad session reports line"
      (Value.as_number (call env result "line" []) = 2.));
  ignore (call env session "clear" []);
  check "clear resets history" (history_size () = 0);
  check "clear resets ans" (Value.as_number (call env session "previous" []) = 0.);
  check "clear resets variables" (not (ok env (calculate "radius")));
  (* Run the actual application, including IO, commands, and EOF handling. *)
  with_file (fun input_path -> with_file (fun output_path ->
    with_file (fun error_path -> with_file (fun session_path ->
      let child = Filename.concat (Unix.getcwd ()) "process_child.exe" in
      let input = String.concat "\n"
        ["x = 5"; "x * 2"; "1/0"; "2+3"; ":vars"; ":history";
         ":save " ^ session_path; ":clear"; ":load " ^ session_path;
         "ans"; ":info " ^ session_path; ":pwd";
         ":exec " ^ child; ":quit"; ""] in
      Out_channel.with_open_bin input_path (fun c -> output_string c input);
      In_channel.with_open_bin input_path (fun input ->
        Out_channel.with_open_bin output_path (fun output ->
          Out_channel.with_open_bin error_path (fun error ->
            let cwd = Unix.getcwd () in
            let pid = Fun.protect ~finally:(fun () -> Unix.chdir cwd) (fun () ->
              Unix.chdir "..";
              Unix.create_process "bin/main.exe"
                [|"troopl"; "examples/calculator/main.tr"|]
                (Unix.descr_of_in_channel input)
                (Unix.descr_of_out_channel output)
                (Unix.descr_of_out_channel error)) in
            let _, status = Unix.waitpid [] pid in
            check "calculator application exits normally"
              (status = Unix.WEXITED 0))));
      let output = read output_path and error = read error_path in
      List.iter (fun expected ->
        check ("calculator output " ^ expected) (contains output expected))
        ["calc> 10"; "x = 5"; "Session saved."; "Session cleared.";
         "Loaded 3 expressions."; "exists: true"; "child-ready"; "Exit code: 0"];
      check "application reports and recovers from errors"
        (contains error "division by zero");
      check "application has no fatal interpreter error"
        (not (contains error "RUNTIME ERROR"))))));
  Printf.printf "%d calculator checks passed\n%!" !checks
