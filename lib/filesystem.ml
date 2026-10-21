let path env value =
  let text = Builtins.string_of_value env value in
  if String.contains text '\000' then Runtime.error "NUL in file path";
  text

let read_handle channel =
  let closed = ref false in
  let handle = Value.uninitialized () in
  Value.add_method handle "read" 1 (fun env args ->
    let count = List.hd args |> Builtins.int_of_value in
    if count <= 0 then Runtime.error "read size must be positive";
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

let metadata env filename =
  let stat =
    try Some (Unix.stat filename) with
    | Unix.Unix_error ((Unix.ENOENT | Unix.ENOTDIR), _, _) -> None
  in
  let value = Value.uninitialized () in
  let boolean name test =
    let result = Builtins.make_boolean env (test stat) in
    Value.add_method value name 0 (fun _ _ -> result)
  in
  let number name get =
    let result = Builtins.make_number env
      (Option.fold ~none:0. ~some:get stat) in
    Value.add_method value name 0 (fun _ _ -> result)
  in
  boolean "exists?" Option.is_some;
  let kind test = Option.fold ~none:false ~some:(fun s ->
    test s.Unix.st_kind) in
  boolean "file?" (kind (( = ) Unix.S_REG));
  boolean "dir?" (kind (( = ) Unix.S_DIR));
  boolean "other?" (kind (fun k -> k <> Unix.S_REG && k <> Unix.S_DIR));
  number "accessed" (fun s -> s.Unix.st_atime);
  number "modified" (fun s -> s.Unix.st_mtime);
  number "size" (fun s -> float s.Unix.st_size);
  Value.finish value

let make () =
  let fs = Value.uninitialized () in
  Value.add_method fs "read" 1 (fun env args ->
    let path = List.hd args |> path env in
    Outcome.attempt env (fun () ->
      In_channel.with_open_bin path (fun channel ->
        In_channel.input_all channel |> Builtins.make_byte_string env)));
  Value.add_method fs "write" 2 (fun env args ->
    match args with
    | [filename; source] ->
        let path = path env filename in
        (* Convert before opening to avoid truncation on invalid characters. *)
        let text = Builtins.string_of_value env source in
        Outcome.attempt env (fun () ->
          Out_channel.with_open_bin path (fun channel ->
            output_string channel text);
          fs)
    | _ -> invalid_arg "wrong arity");
  Value.add_method fs "open-read" 1 (fun env args ->
    let path = List.hd args |> path env in
    Outcome.attempt env (fun () -> open_in_bin path |> read_handle));
  Value.add_method fs "open-write" 1 (fun env args ->
    let path = List.hd args |> path env in
    Outcome.attempt env (fun () -> open_out_bin path |> write_handle));
  Value.add_method fs "metadata" 1 (fun env args ->
    let filename = path env (List.hd args) in
    Outcome.attempt env (fun () -> metadata env filename));
  Value.add_method fs "real-path" 1 (fun env args ->
    let filename = path env (List.hd args) in
    Outcome.attempt env (fun () ->
      Unix.realpath filename |> Builtins.make_byte_string env));
  Value.add_method fs "rename" 2 (fun env args ->
    match args with
    | [source; target] ->
        let source = path env source and target = path env target in
        Outcome.attempt env (fun () -> Unix.rename source target; fs)
    | _ -> invalid_arg "wrong arity");
  List.iter (fun (name, operation) ->
    Value.add_method fs name 1 (fun env args ->
      let filename = path env (List.hd args) in
      Outcome.attempt env (fun () -> operation filename; fs)))
    ["make-dir", (fun dir -> Unix.mkdir dir 0o755);
     "remove", Unix.unlink; "remove-dir", Unix.rmdir;
     "working-dir", Unix.chdir];
  Value.add_method fs "working-dir" 0 (fun env _ ->
    Outcome.attempt env (fun () ->
      Unix.getcwd () |> Builtins.make_byte_string env));
  Value.add_method fs "list-dir" 1 (fun env args ->
    let directory = path env (List.hd args) in
    Outcome.attempt env (fun () ->
      let names = Sys.readdir directory in
      Array.sort String.compare names;
      Array.map (Builtins.make_byte_string env) names
      |> Builtins.make_list env));
  Value.finish fs
