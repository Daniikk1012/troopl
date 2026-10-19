(** Use regular binary temporary files for child stdio. This avoids pipe
    deadlocks when a child writes large stdout/stderr before reading stdin. *)
let with_temporary f =
  let filename, channel = Filename.open_temp_file ~mode:[Open_binary]
    "troopl-process-" ".bin" in
  Fun.protect ~finally:(fun () ->
    close_out_noerr channel;
    try Sys.remove filename with Sys_error _ -> ())
    (fun () -> close_out channel; f filename)

let with_descriptor filename flags f =
  let descriptor = Unix.openfile filename (Unix.O_CLOEXEC :: flags) 0o600 in
  Fun.protect ~finally:(fun () -> Unix.close descriptor)
    (fun () -> f descriptor)

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

let execute env argv input =
  with_temporary (fun stdin_path ->
    with_temporary (fun stdout_path ->
      with_temporary (fun stderr_path ->
        Out_channel.with_open_bin stdin_path (fun channel ->
          output_string channel input);
        let status =
          with_descriptor stdin_path [Unix.O_RDONLY] (fun stdin ->
            with_descriptor stdout_path [Unix.O_WRONLY; Unix.O_TRUNC]
              (fun stdout ->
                with_descriptor stderr_path [Unix.O_WRONLY; Unix.O_TRUNC]
                  (fun stderr ->
                    Unix.create_process argv.(0) argv stdin stdout stderr
                    |> wait)))
        in
        let read filename =
          In_channel.with_open_bin filename In_channel.input_all
          |> Builtins.make_byte_string env
        in
        let stdout = read stdout_path in
        let stderr = read stderr_path in
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
        Value.finish result)))

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
