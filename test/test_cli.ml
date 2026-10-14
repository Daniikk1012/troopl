open Troopl

let check label condition = if not condition then failwith label
let read filename = In_channel.with_open_bin filename In_channel.input_all
let contains text needle =
  let rec scan i =
    i + String.length needle <= String.length text
    && (String.sub text i (String.length needle) = needle || scan (i + 1))
  in
  scan 0

let run filename =
  let output_path = Filename.temp_file "troopl-cli-" ".out" in
  let error_path = Filename.temp_file "troopl-cli-" ".err" in
  Fun.protect
    ~finally:(fun () -> Sys.remove output_path; Sys.remove error_path)
    (fun () ->
      let output = Unix.openfile output_path [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
      let error = Unix.openfile error_path [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
      let pid =
        Fun.protect ~finally:(fun () -> Unix.close output; Unix.close error)
          (fun () ->
            Unix.create_process "../bin/main.exe"
              [|"troopl"; filename|] Unix.stdin output error)
      in
      let _, status = Unix.waitpid [] pid in
      status, read output_path, read error_path)

let with_source source f =
  let filename = Filename.temp_file "troopl-source-" ".tr" in
  Fun.protect ~finally:(fun () -> Sys.remove filename) (fun () ->
    Out_channel.with_open_bin filename (fun c -> output_string c source);
    f filename)

let () =
  List.iter (fun (source, suffix) ->
    with_source source (fun filename ->
      let status, output, error = run filename in
      check "CLI failure status" (status = Unix.WEXITED 1);
      check "CLI error does not print to stdout" (output = "");
      check "CLI precise error"
        (contains error (filename ^ ":" ^ suffix))))
    ["\nMissing", "2:1: LOWERING ERROR";
     "(", "1:2: PARSER ERROR";
     "1a", "1:1: LEXER ERROR";
     "\n\"abc\" at 99", "2:7: RUNTIME ERROR"];
  with_source "E {() filename \"virtual.tr\"}\n(env run E [1 + {}])"
    (fun filename ->
      let status, _, error = run filename in
      check "dynamic filename status" (status = Unix.WEXITED 1);
      check "dynamic filename report"
        (contains error "virtual.tr:2:15: RUNTIME ERROR"));
  with_source "E {() filename {}}\n(env run E [1 + {}])"
    (fun filename ->
      let status, _, error = run filename in
      check "invalid filename status" (status = Unix.WEXITED 1);
      check "invalid filename fallback"
        (contains error (filename ^ ":2:15: RUNTIME ERROR")));
  with_source "(io print \"works\")" (fun filename ->
    let status, output, error = run filename in
    check "CLI success" (status = Unix.WEXITED 0);
    check "CLI stdout" (output = "works\n");
    check "CLI quiet stderr" (error = ""));
  with_source "(exit 7)" (fun filename ->
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
  check "missing file diagnostic"
    (contains error (missing ^ ": IO ERROR"));
  check "file IO error has no invented position"
    (not (contains error ":1:1:"));
  print_endline "CLI filename, position, IO, exit and crash checks passed"
