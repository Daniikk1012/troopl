let rec wait pid =
  try snd (Unix.waitpid [] pid) with
  | Unix.Unix_error (Unix.EINTR, _, _) -> (wait [@tailcall]) pid

let command env source =
  let size = Builtins.size_of_value env source in
  if size = 0 then Runtime.error "empty command argument list";
  let at = Value.get_method source "at" 1 env in
  Array.init size (fun i ->
    let value = Runtime.resume (fun () ->
      at [Builtins.make_number env (float i)]) in
    let text = Builtins.string_of_value env value in
    if String.contains text '\000' then Runtime.error "NUL in command argument";
    text)

(* A child may exit without reading stdin. Suppress only the SIGPIPE generated
   by this write, preserving the calling thread's mask and pending signals. *)
let write_pipe fd input offset count =
  if Sys.os_type = "Win32" then
    Unix.single_write_substring fd input offset count
  else
    let mask = Unix.sigprocmask Unix.SIG_BLOCK [Sys.sigpipe] in
    Fun.protect
      ~finally:(fun () -> ignore (Unix.sigprocmask Unix.SIG_SETMASK mask))
      (fun () ->
        let pending = List.mem Sys.sigpipe (Unix.sigpending ()) in
        try Unix.single_write_substring fd input offset count with
        | Unix.Unix_error (Unix.EPIPE, _, _) as error ->
            if not pending && List.mem Sys.sigpipe (Unix.sigpending ()) then
              ignore (Thread.wait_signal [Sys.sigpipe]);
            raise error)

(* Drain both outputs while feeding stdin, rather than waiting on one stream.
   Each ready descriptor gets at most one chunk per turn to keep things fair. *)
let poll close stdin stdout stderr input =
  List.iter Unix.set_nonblock [stdin; stdout; stderr];
  let output = Buffer.create 4096 and error = Buffer.create 4096 in
  let readers = ref [stdout, output; stderr, error] in
  let writer = ref (Some stdin) and offset = ref 0 in
  let finish_input () = close stdin; writer := None in
  if input = "" then finish_input ();
  let bytes = Bytes.create 16384 in
  let rec loop () =
    if !readers <> [] || Option.is_some !writer then (
      let readable = List.map fst !readers in
      let writable = Option.to_list !writer in
      let ready_read, ready_write, _ =
        try Unix.select readable writable [] (-1.) with
        | Unix.Unix_error (Unix.EINTR, _, _) -> [], [], []
      in
      List.iter (fun (fd, buffer) ->
        if List.mem fd ready_read then
          try
            let count = Unix.read fd bytes 0 (Bytes.length bytes) in
            if count = 0 then (
              close fd;
              readers := List.filter (fun (other, _) -> other <> fd) !readers)
            else Buffer.add_subbytes buffer bytes 0 count
          with Unix.Unix_error
            ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> ())
        !readers;
      (match !writer with
       | Some fd when List.mem fd ready_write ->
           (try
              let count = min 16384 (String.length input - !offset) in
              let written = write_pipe fd input !offset count in
              offset := !offset + written;
              if !offset = String.length input then finish_input ()
            with
            | Unix.Unix_error (Unix.EPIPE, _, _) -> finish_input ()
            | Unix.Unix_error
                ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> ())
       | _ -> ());
      (loop [@tailcall]) ())
  in
  loop ();
  Buffer.contents output, Buffer.contents error

(* Native Windows cannot make anonymous pipes nonblocking through Unix.
   Reader threads release the OCaml runtime during IO; the calling thread can
   feed stdin without either child's output pipe filling up and deadlocking.
   Workers only touch host bytes, never Troopl values or diagnostic state. *)
let threaded join start close stdin stdout stderr input =
  let read fd () =
    let buffer = Buffer.create 4096 and bytes = Bytes.create 16384 in
    let rec loop () =
      let count =
        try Unix.read fd bytes 0 (Bytes.length bytes) with
        | Unix.Unix_error (Unix.EINTR, _, _) -> -1
      in
      if count <> 0 then (
        if count > 0 then Buffer.add_subbytes buffer bytes 0 count;
        (loop [@tailcall]) ())
    in
    loop ();
    Buffer.contents buffer
  in
  let output = start (read stdout) in
  let error = start (read stderr) in
  let rec write offset =
    if offset < String.length input then (
      let count = min 16384 (String.length input - offset) in
      let written =
        try write_pipe stdin input offset count with
        | Unix.Unix_error (Unix.EINTR, _, _) -> 0
      in
      (write [@tailcall]) (offset + written))
  in
  (try write 0 with Unix.Unix_error (Unix.EPIPE, _, _) -> ());
  close stdin;
  let output = join output in
  let error = join error in
  output, error

let capture argv input =
  let descriptors = ref [] and child = ref None and workers = ref [] in
  let pipe () =
    let read, write = Unix.pipe ~cloexec:true () in
    descriptors := read :: write :: !descriptors;
    read, write
  in
  let close fd =
    descriptors := List.filter (( <> ) fd) !descriptors;
    try Unix.close fd with Unix.Unix_error _ -> ()
  in
  let terminate () = Option.iter (fun pid ->
    try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ()) !child in
  let join_worker thread =
    Thread.join thread;
    workers := List.filter (fun other -> other != thread) !workers
  in
  let start f =
    let result = ref None in
    let thread = Thread.create (fun () ->
      result := Some (try Ok (f ()) with error ->
        terminate ();
        Error error)) () in
    workers := thread :: !workers;
    thread, result
  in
  let join (thread, result) =
    join_worker thread;
    match !result with
    | Some (Ok value) -> value
    | Some (Error error) -> raise error
    | None -> assert false
  in
  Fun.protect ~finally:(fun () ->
    terminate ();
    List.iter join_worker !workers;
    List.iter close !descriptors;
    Option.iter (fun pid ->
      try ignore (wait pid) with Unix.Unix_error _ -> ()) !child)
    (fun () ->
      let stdin_read, stdin_write = pipe () in
      let stdout_read, stdout_write = pipe () in
      let stderr_read, stderr_write = pipe () in
      let pid = Unix.create_process argv.(0) argv stdin_read stdout_write
        stderr_write in
      child := Some pid;
      List.iter close [stdin_read; stdout_write; stderr_write];
      let output, error =
        if Sys.win32 then
          threaded join start close stdin_write stdout_read stderr_read input
        else poll close stdin_write stdout_read stderr_read input
      in
      let status = wait pid in
      child := None;
      output, error, status)

let execute env argv input =
  let output, error, status = capture argv input in
  let stdout = Builtins.make_byte_string env output in
  let stderr = Builtins.make_byte_string env error in
  (* A signal has no exit status. Use 128 for abnormal termination. *)
  let code = match status with
    | Unix.WEXITED code -> code
    | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 128
  in
  let code = Builtins.make_number env (float code) in
  let result = Value.uninitialized () in
  Value.add_method result "stdout" 0 (fun _ _ -> stdout);
  Value.add_method result "stderr" 0 (fun _ _ -> stderr);
  Value.add_method result "exit-code" 0 (fun _ _ -> code);
  Value.finish result

let make () =
  let system = Value.uninitialized () in
  let run env source input =
    let argv = command env source in
    Outcome.attempt env (fun () -> execute env argv input)
  in
  Value.add_method system "run" 1 (fun env args ->
    run env (List.hd args) "");
  Value.add_method system "run" 2 (fun env args ->
    match args with
    | [source; input] ->
        let input = Builtins.string_of_value env input in
        run env source input
    | _ -> invalid_arg "wrong arity");
  Value.add_method system "time" 0 (fun env _ ->
    Builtins.make_number env (Unix.gettimeofday ()));
  Value.add_method system "exit" 1 (fun _ args ->
    List.hd args |> Builtins.int_of_value |> exit);
  Value.finish system
