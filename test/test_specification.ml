open Troopl

let checks = ref 0
let check label condition =
  incr checks;
  if not condition then failwith label
let call env value name args =
  Value.get_method value name (List.length args) env args
let n env i = Builtins.make_number env (float i)
let s = Builtins.make_byte_string
let text = Builtins.string_of_value
let read path = In_channel.with_open_bin path In_channel.input_all
let truth env value =
  let yes = Value.empty () and no = Value.empty () in
  call env value "then-else" [yes; no] == yes
let ok env value = call env value "ok?" [] |> truth env
let size env value = call env value "size" [] |> Builtins.int_of_value
let at env value i = call env value "at" [n env i]
let list env values = Builtins.make_list env (Array.of_list values)
let fails f = try ignore (f ()); false with Runtime.Error _ -> true

let with_directory f =
  let dir = Filename.temp_file "troopl-spec-" ".dir" in
  Sys.remove dir;
  Unix.mkdir dir 0o700;
  Fun.protect ~finally:(fun () ->
    Array.iter (fun name ->
      let path = Filename.concat dir name in
      if (Unix.lstat path).st_kind = Unix.S_DIR then Unix.rmdir path
      else Unix.unlink path) (Sys.readdir dir);
    Unix.rmdir dir) (fun () -> f dir)

let () =
  let env = Env.make () in
  let utf8 = call env env "utf-8" [] in
  let decode raw =
    let bytes = Bytes.of_string raw |> Builtins.list_of_bytes env in
    call env utf8 "from-bytes" [bytes]
  in
  let encode value =
    call env utf8 "to-bytes" [value] |> Builtins.bytes_of_value env
    |> Bytes.to_string
  in
  let all_bytes = String.init 256 Char.chr in
  let source = decode all_bytes in
  check "all byte values roundtrip" (encode source = all_bytes);
  check "host conversion is lossless" (text env source = all_bytes);
  check "invalid bytes are negative"
    (Value.as_number (at env (decode "A\255") 1) = -255.);
  let unicode = decode "я🙂" in
  check "valid scalars decoded" (size env unicode = 2);
  check "stable code object" (at env unicode 0 == at env unicode 0);
  check "stable size object"
    (call env unicode "size" [] == call env unicode "size" []);
  check "strict encoding rejects escapes"
    (fails (fun () -> call env utf8 "from-string" [source]));
  let escapes = list env (List.init 255 (fun i -> n env (-i - 1))) in
  check "all negative escapes accepted"
    (encode escapes = String.init 255 (fun i -> Char.chr (i + 1)));
  check "invalid negative escape rejected"
    (fails (fun () -> encode (list env [n env (-256)])));
  let random = Random.State.make [|17; 101|] in
  for length = 0 to 128 do
    let raw = String.init length (fun _ ->
      Random.State.int random 256 |> Char.chr) in
    check "random byte roundtrip" (encode (decode raw) = raw)
  done;
  List.iter (fun raw ->
    check "incomplete bytes preserved" (encode (decode raw) = raw))
    ["\194"; "\226\130"; "\240\159\153"; "\237\160\128"];
  let fs = call env env "fs" [] in
  with_directory (fun dir ->
    let path name = Filename.concat dir name |> s env in
    let file = path "bytes.bin" in
    let written = call env fs "write" [file; source] in
    check "write returns filesystem" (ok env written);
    check "write result supports metadata"
      (ok env (call env written "metadata" [file]));
    let read = call env fs "read" [file] in
    check "read returns lossless string"
      (ok env read && text env read = all_bytes);
    let metadata = call env fs "metadata" [file] in
    check "metadata file exists"
      (ok env metadata && truth env (call env metadata "exists?" []));
    check "metadata file classification"
      (truth env (call env metadata "file?" [])
       && not (truth env (call env metadata "dir?" []))
       && not (truth env (call env metadata "other?" [])));
    check "metadata byte size" (size env metadata = 256);
    List.iter (fun field ->
      check "metadata timestamp"
        (Value.as_number (call env metadata field []) > 0.))
      ["accessed"; "modified"];
    let missing = call env fs "metadata" [path "missing"] in
    check "missing metadata succeeds" (ok env missing);
    List.iter (fun field ->
      check "missing metadata false"
        (not (truth env (call env missing field []))))
      ["exists?"; "file?"; "dir?"; "other?"];
    List.iter (fun field ->
      check "missing metadata zero"
        (Value.as_number (call env missing field []) = 0.))
      ["accessed"; "modified"; "size"];
    check "mkdir succeeds" (ok env (call env fs "make-dir" [path "sub"]));
    let directory = call env fs "metadata" [path "sub"] in
    check "metadata directory" (truth env (call env directory "dir?" []));
    let names = call env fs "list-dir" [s env dir] in
    check "directory listing strings"
      (ok env names && size env names = 2
       && text env (at env names 0) = "bytes.bin"
       && text env (at env names 1) = "sub");
    let full = call env fs "real-path" [file] in
    check "real path" (ok env full && text env full = Unix.realpath
      (Filename.concat dir "bytes.bin"));
    if not Sys.win32 then (
      Unix.symlink "bytes.bin" (Filename.concat dir "link");
      let link = call env fs "real-path" [path "link"] in
      check "real path follows symlink" (text env link = text env full);
      ignore (call env fs "remove" [path "link"]));
    let cwd = Unix.getcwd () in
    Fun.protect ~finally:(fun () -> Unix.chdir cwd) (fun () ->
      check "change working directory"
        (ok env (call env fs "working-dir" [s env dir]));
      let result = call env fs "working-dir" [] in
      check "read working directory"
        (ok env result && text env result = Unix.getcwd ()));
    check "rename succeeds"
      (ok env (call env fs "rename" [file; path "renamed"]));
    check "rename removed old name"
      (not (truth env (call env (call env fs "metadata" [file]) "exists?" [])));
    check "remove directory succeeds"
      (ok env (call env fs "remove-dir" [path "sub"]));
    check "missing path failure is recoverable"
      (not (ok env (call env fs "remove" [path "missing"])));
    check "directory listing failure is recoverable"
      (not (ok env (call env fs "list-dir" [path "missing"])));
    if Sys.os_type = "Unix" then (
      let name = path "raw-\255" in
      check "non-UTF8 filename write"
        (ok env (call env fs "write" [name; s env "raw\255"]));
      check "non-UTF8 filename read"
        (text env (call env fs "read" [name]) = "raw\255");
      let names = call env fs "list-dir" [s env dir] in
      check "non-UTF8 directory entry survives"
        (List.init (size env names) (fun i -> text env (at env names i))
         |> List.mem "raw-\255")));
  let executable = Filename.concat (Unix.getcwd ()) "process_child.exe" in
  let system = call env env "system" [] in
  let argv mode = list env [s env executable; s env mode] in
  let result = call env system "run" [argv "echo"; source] in
  check "process succeeded" (ok env result);
  check "process stdin/stdout binary exact"
    (text env (call env result "stdout" []) = "out:" ^ all_bytes ^ "\255");
  check "process stderr separate/lossless"
    (text env (call env result "stderr" []) = "error\254");
  check "process exit status"
    (Value.as_number (call env result "exit-code" []) = 0.);
  let result = call env system "run" [argv "exit"] in
  check "nonzero exit is completed result"
    (ok env result && Value.as_number (call env result "exit-code" []) = 7.);
  let result = call env system "run" [argv "empty"] in
  check "default stdin empty"
    (ok env result && Value.as_number (call env result "exit-code" []) = 0.);
  let result = call env system "run" [list env
    [s env executable; s env "args"; s env "a b"; s env "$(not-a-shell)"]] in
  check "arguments passed literally"
    (text env (call env result "stdout" []) = "a b\n$(not-a-shell)\n");
  let result = call env system "run"
    [argv "flood"; s env (String.make 100000 'c')] in
  check "large process stdout"
    (text env (call env result "stdout" []) = String.make 70000 'a' ^ "100000");
  check "large process stderr"
    (text env (call env result "stderr" []) = String.make 70000 'b');
  let () =
    let mask = if Sys.win32 then [] else Unix.sigprocmask Unix.SIG_BLOCK [] in
    let input = s env (String.make 100000 'x' ^ "\255") in
    let result = call env system "run" [argv "duplex"; input] in
    check "duplex process success" (ok env result);
    List.iter (fun stream ->
      check "duplex pipe exact bytes"
        (text env (call env result stream []) = text env input))
      ["stdout"; "stderr"];
    let result = call env system "run" [argv "early"; input] in
    check "early exit succeeds" (ok env result);
    check "early exit stdout retained"
      (text env (call env result "stdout" []) = "early\255");
    check "early exit stderr retained"
      (text env (call env result "stderr" []) = "closed\254");
    if not Sys.win32 then
      check "closed stdin preserves caller signal mask"
        (Unix.sigprocmask Unix.SIG_BLOCK [] = mask);
    let result = call env system "run" [argv "flood"; input] in
    check "threaded pipes drain full stdout before stdin"
      (text env (call env result "stdout" [])
       = String.make 70000 'a' ^ "100001");
    check "threaded pipes drain full stderr before stdin"
      (text env (call env result "stderr" []) = String.make 70000 'b');
    let result = call env system "run" [argv "empty"] in
    check "threaded pipes send EOF for empty stdin"
      (ok env result && Value.as_number (call env result "exit-code" []) = 0.);
    check "threaded pipes clean up a launch failure"
      (not (ok env (call env system "run" [list env [s env
        (executable ^ ".missing")]])))
  in
  check "missing command is recoverable"
    (not (ok env (call env system "run" [list env [s env
      (executable ^ ".missing")]])));
  check "empty command crashes"
    (fails (fun () -> call env system "run" [list env []]));
  check "NUL argument crashes"
    (fails (fun () -> call env system "run" [list env [s env "bad\000path"]]));
  let before = Unix.gettimeofday () in
  let now = call env system "time" [] |> Value.as_number in
  check "system time timestamp" (now >= before && now <= Unix.gettimeofday ());
  (* The one-argument overload must not construct a Troopl stdin string. *)
  let strings = ref 0 in
  let core = call env env "core" [] in
  let extension = call env core "extend" [] in
  let custom_extension = Value.uninitialized () in
  Value.add_methods custom_extension extension;
  Value.add_method custom_extension "string" 1 (fun _ args ->
    incr strings;
    List.hd args);
  Value.initialize custom_extension;
  let custom_core = Value.uninitialized () in
  Value.add_methods custom_core core;
  Value.add_method custom_core "extend" 0 (fun _ _ -> custom_extension);
  Value.initialize custom_core;
  let custom = Value.uninitialized () in
  Value.add_methods custom env;
  Value.add_method custom "core" 0 (fun _ _ -> custom_core);
  Value.initialize custom;
  let args = argv "empty" in
  ignore (call custom system "run" [args]);
  check "only stdout/stderr strings constructed" (!strings = 2);
  let filename_env = Env.make ~filename:"raw-\255" () in
  check "environment filename is lossless"
    (text filename_env (call filename_env filename_env "filename" [])
     = "raw-\255");
  with_directory (fun dir ->
    let input_path = Filename.concat dir "in" in
    let output_path = Filename.concat dir "out" in
    let error_path = Filename.concat dir "err" in
    Out_channel.with_open_bin input_path (fun c ->
      output_string c "\255\r\n");
    In_channel.with_open_bin input_path (fun input ->
      Out_channel.with_open_bin output_path (fun output ->
        Out_channel.with_open_bin error_path (fun error ->
          let env = Env.make ~input ~output ~error () in
          let io = call env env "io" [] in
          let line = call env io "read-line" [] in
          check "console input lossless/CR retained"
            (ok env line && text env line = "\255\r");
          ignore (call env io "raw-print" [s env "\255"]);
          let flushed = call env io "flush" [] in
          check "stdout flush returns IO"
            (ok env flushed && read output_path = "\255");
          let err = call env io "error" [] in
          ignore (call env err "raw-print" [s env "\254"]);
          let flushed = call env err "flush" [] in
          check "stderr flush returns error IO"
            (ok env flushed && read error_path = "\254")))));
  Printf.printf "%d Version 0.1 checks passed\n%!" !checks
