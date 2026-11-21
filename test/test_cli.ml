open Troopl

let check label condition = if not condition then failwith label
let read filename = In_channel.with_open_bin filename In_channel.input_all

let contains text needle =
  let rec scan i =
    i + String.length needle <= String.length text
    && (String.sub text i (String.length needle) = needle || scan (i + 1))
  in
  scan 0

let run ?(arguments = []) ?(environment = Unix.environment ()) filename =
  let output_path = Filename.temp_file "troopl-cli-" ".out" in
  let error_path = Filename.temp_file "troopl-cli-" ".err" in
  Fun.protect
    ~finally:(fun () ->
      Sys.remove output_path;
      Sys.remove error_path)
    (fun () ->
      let output =
        Unix.openfile output_path [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600
      in
      let error =
        Unix.openfile error_path [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600
      in
      let pid =
        Fun.protect
          ~finally:(fun () ->
            Unix.close output;
            Unix.close error)
          (fun () ->
            Unix.create_process_env "../bin/main.exe"
              (Array.of_list ("troopl" :: filename :: arguments))
              environment Unix.stdin output error)
      in
      let _, status = Unix.waitpid [] pid in
      (status, read output_path, read error_path))

let with_source source f =
  let filename = Filename.temp_file "troopl-source-" ".tr" in
  Fun.protect
    ~finally:(fun () -> Sys.remove filename)
    (fun () ->
      Out_channel.with_open_bin filename (fun c -> output_string c source);
      f filename)

let () =
  List.iter
    (fun (source, suffix) ->
      with_source source (fun filename ->
          let status, output, error = run filename in
          check "CLI failure status" (status = Unix.WEXITED 1);
          check "CLI error does not print to stdout" (output = "");
          check "CLI precise error" (contains error (filename ^ ":" ^ suffix))))
    [
      ("\nMissing", "2:1: LOWERING ERROR");
      ("(", "1:2: PARSER ERROR");
      ("1a", "1:1: LEXER ERROR");
      ("\n\"abc\" at 99", "2:7: RUNTIME ERROR");
    ];
  with_source "E {() filename \"virtual.tr\"}\n(env run E [1 + {}])"
    (fun filename ->
      let status, _, error = run filename in
      check "dynamic filename status" (status = Unix.WEXITED 1);
      check "dynamic filename report"
        (contains error "virtual.tr:2:15: RUNTIME ERROR"));
  with_source "E {() filename {}}\n(env run E [1 + {}])" (fun filename ->
      let status, _, error = run filename in
      check "invalid filename status" (status = Unix.WEXITED 1);
      check "invalid filename fallback"
        (contains error (filename ^ ":2:15: RUNTIME ERROR")));
  with_source "(io print \"works\")" (fun filename ->
      let status, output, error = run filename in
      check "CLI success" (status = Unix.WEXITED 0);
      check "CLI stdout" (output = "works\n");
      check "CLI quiet stderr" (error = ""));
  with_source "(system exit 7)" (fun filename ->
      let status, _, error = run filename in
      check "exit capability" (status = Unix.WEXITED 7);
      check "exit quiet stderr" (error = ""));
  with_source "(crash \"intentional\")" (fun filename ->
      let status, _, error = run filename in
      check "crash capability" (status = Unix.WEXITED 1);
      check "crash message" (contains error "intentional"));
  let missing = Filename.temp_file "troopl-missing-" ".tr" in
  Sys.remove missing;
  let status, _, error = run missing in
  check "missing file status" (status = Unix.WEXITED 1);
  check "missing file diagnostic" (contains error (missing ^ ": IO ERROR"));
  check "file IO error has no invented position" (not (contains error ":1:1:"));
  with_source "(io print (system args at 0)) (io print (system args at 1))"
    (fun filename ->
      let status, output, error = run ~arguments:[ "hello world" ] filename in
      check "CLI accepts program arguments" (status = Unix.WEXITED 0);
      check "CLI exposes filename and exact argument"
        (output = filename ^ "\nhello world\n");
      check "CLI arguments quiet stderr" (error = ""));
  let status, output, _ = run "--help" in
  check "help status" (status = Unix.WEXITED 0);
  check "help usage" (contains output "usage: troopl");
  let status, output, _ = run "--version" in
  check "version status" (status = Unix.WEXITED 0);
  check "version spec" (contains output "specification v0.2");
  let status, _, error = run "--bogus" in
  check "unknown option status" (status = Unix.WEXITED 1);
  check "unknown option usage" (contains error "unknown option --bogus");
  with_source "X 1\n(io print \"never\")" (fun filename ->
      let status, output, _ = run "--tokens" ~arguments:[ filename ] in
      check "tokens status" (status = Unix.WEXITED 0);
      check "tokens dump"
        (contains output "1:1: Variable X" && contains output "1:3: Number 1.");
      check "tokens do not run" (not (contains output "never\n"));
      let status, output, _ = run "--ir" ~arguments:[ filename ] in
      check "ir status" (status = Unix.WEXITED 0);
      check "ir dump" (contains output "Text \"never\"");
      let status, output, _ = run "--ast" ~arguments:[ filename ] in
      check "ast status" (status = Unix.WEXITED 0);
      check "ast dump" (contains output "Definition X"));
  (* A small stack limit makes deep guest recursion overflow quickly. *)
  let environment =
    Unix.environment () |> Array.to_list
    |> List.filter (fun entry ->
        not (String.starts_with ~prefix:"OCAMLRUNPARAM=" entry))
    |> List.cons "OCAMLRUNPARAM=l=1M"
    |> Array.of_list
  in
  with_source "F {go N (N + (F go (N + 1)))}\nF go 0" (fun filename ->
      let status, output, error = run ~environment filename in
      check "stack overflow status" (status = Unix.WEXITED 1);
      check "stack overflow stdout" (output = "");
      check "stack overflow position"
        (contains error (filename ^ ":1:")
        && contains error "RUNTIME ERROR: stack overflow"));
  (* Standard library crashes: everything else about the library is tested
     in Troopl itself (stdlib/test), which cannot observe a crash. *)
  let with_stdlib body =
    with_source
      ("Filename \"../stdlib/stdlib.tr\"\n\
        Source (fs read Filename)\n\
        (Source ok? then-else [{}] [(crash (Source message))] run)\n\
        Loader {() filename (Filename)}\n\
        Stdlib (env run Loader [(eval Source)])\n\
        (env run Stdlib [" ^ body ^ "])\n")
  in
  List.iter
    (fun (body, message) ->
      with_stdlib body (fun filename ->
          let status, _, error = run filename in
          check ("stdlib crash status: " ^ body) (status = Unix.WEXITED 1);
          check ("stdlib crash message: " ^ body) (contains error message)))
    [
      ("\"abc\" reverse at 3", "RUNTIME ERROR: index out of bounds");
      ("array pop", "RUNTIME ERROR");
    ];
  let module_path = Filename.temp_file "troopl-module-" ".tr" in
  Fun.protect
    ~finally:(fun () -> Sys.remove module_path)
    (fun () ->
      Out_channel.with_open_bin module_path (fun c ->
          output_string c "{run ({} missing)}");
      with_stdlib
        ("import \"" ^ module_path ^ "\" run")
        (fun filename ->
          let status, _, error = run filename in
          check "imported method crash status" (status = Unix.WEXITED 1);
          check "imported method reports module filename and position"
            (contains error (module_path ^ ":1:10: RUNTIME ERROR"))));
  print_endline "CLI filename, arguments, IO, exit and crash checks passed"
