let read_handle channel =
  let closed = ref false in
  let handle = Value.uninitialized () in
  Value.add_method handle "read" 1 (fun env args ->
    let count = List.hd args |> Builtins.int_of_value in
    if count < 0 then Runtime.error "negative read size";
    if !closed then Outcome.failure env "file is closed"
    else Outcome.attempt env (fun () ->
      let capacity = min count 65536 in
      let buffer = Bytes.create capacity in
      let used = input channel buffer 0 capacity in
      Builtins.list_of_bytes env (Bytes.sub buffer 0 used)));
  Value.add_method handle "close" 0 (fun env _ ->
    if !closed then Outcome.failure env "file is already closed"
    else Outcome.attempt env (fun () ->
      closed := true;
      close_in channel;
      Value.empty ()));
  Value.finish handle

let write_handle channel =
  let closed = ref false in
  let handle = Value.uninitialized () in
  Value.add_method handle "write" 1 (fun env args ->
    if !closed then Outcome.failure env "file is closed"
    else
      let bytes = List.hd args |> Builtins.bytes_of_value env in
      Outcome.attempt env (fun () ->
        output_bytes channel bytes;
        handle));
  Value.add_method handle "close" 0 (fun env _ ->
    if !closed then Outcome.failure env "file is already closed"
    else Outcome.attempt env (fun () ->
      closed := true;
      close_out channel;
      Value.empty ()));
  Value.finish handle

let make () =
  let fs = Value.uninitialized () in
  Value.add_method fs "read" 1 (fun env args ->
    let path = List.hd args |> Builtins.string_of_value env in
    Outcome.attempt env (fun () ->
      In_channel.with_open_bin path (fun channel ->
        In_channel.input_all channel |> Bytes.of_string
        |> Builtins.list_of_bytes env)));
  Value.add_method fs "write" 2 (fun env args ->
    match args with
    | [path; source] ->
        let path = Builtins.string_of_value env path in
        (* Validate before opening: invalid bytes must not truncate the file. *)
        let bytes = Builtins.bytes_of_value env source in
        Outcome.attempt env (fun () ->
          Out_channel.with_open_bin path (fun channel ->
            output_bytes channel bytes);
          Value.empty ())
    | _ -> invalid_arg "wrong arity");
  Value.add_method fs "open-read" 1 (fun env args ->
    let path = List.hd args |> Builtins.string_of_value env in
    Outcome.attempt env (fun () -> open_in_bin path |> read_handle));
  Value.add_method fs "open-write" 1 (fun env args ->
    let path = List.hd args |> Builtins.string_of_value env in
    Outcome.attempt env (fun () -> open_out_bin path |> write_handle));
  Value.finish fs
