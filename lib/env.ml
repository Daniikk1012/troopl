let make_io ~input ~output ~error =
  set_binary_mode_in input true;
  set_binary_mode_out output true;
  set_binary_mode_out error true;
  let writer channel =
    let value = Value.uninitialized () in
    let print newline env args =
      let text = List.hd args |> Builtins.string_of_value env in
      Outcome.attempt env (fun () ->
        output_string channel text;
        if newline then (output_char channel '\n'; flush channel);
        value)
    in
    Value.add_method_id value Native_selectors.id_print_1 (print true);
    Value.add_method_id value Native_selectors.id_raw_print_1 (print false);
    Value.add_method_id value Native_selectors.id_write_1 (fun env args ->
      let bytes = Builtins.bytes_of_value env (List.hd args) in
      Outcome.attempt env (fun () -> output_bytes channel bytes; value));
    Value.add_method_id value Native_selectors.id_flush_0 (fun env _ ->
      Outcome.attempt env (fun () -> flush channel; value));
    value
  in
  let err = writer error |> Value.finish in
  let io = writer output in
  Value.add_method_id io Native_selectors.id_error_0 (fun _ _ -> err);
  Value.add_method_id io Native_selectors.id_read_line_0 (fun env _ ->
    try
      let text = input_line input in
      Builtins.make_byte_string env text |> Outcome.success env
    with
    | End_of_file ->
        let eof = Builtins.make_boolean env true in
        Outcome.failure ~fields:["eof?", eof] env "end of input"
    | Sys_error message ->
        let eof = Builtins.make_boolean env false in
        Outcome.failure ~fields:["eof?", eof] env message);
  Value.add_method_id io Native_selectors.id_read_1 (fun env args ->
    let count = Builtins.int_of_value (List.hd args) in
    if count <= 0 then Runtime.error "read size must be positive";
    Outcome.attempt env (fun () ->
      let bytes = Bytes.create (min count 65536) in
      let used = Stdlib.input input bytes 0 (Bytes.length bytes) in
      Builtins.list_of_bytes env (Bytes.sub bytes 0 used)));
  Value.finish io

let environment_control () =
  let value = Value.uninitialized () in
  Value.add_method_id value Native_selectors.id_run_2 (fun _ values ->
    match values with
    | [env; block] ->
        Diagnostics.set_environment env;
        let run = Value.get_method_id block Native_selectors.id_run_0 in
        (run [@tailcall]) env []
    | _ -> invalid_arg "wrong arity");
  Value.add_method_id value Native_selectors.id_bind_2 (fun _ values ->
    match values with
    | [env; value] ->
        Value.bind ~before:(fun () -> Diagnostics.set_environment env) env value
    | _ -> invalid_arg "wrong arity");
  Value.finish value

let from_sequence env sequence =
  let values = Dynarray.create () in
  let rec loop sequence =
    let node = Runtime.resume (fun () ->
      Value.get_method_id sequence Native_selectors.id_run_0 env []) in
    let condition = Runtime.resume (fun () ->
      Value.get_method_id node Native_selectors.id_cons__0 env []) in
    let branch body =
      let block = Value.uninitialized () in
      Value.add_method_id block Native_selectors.id_run_0 (fun _ _ -> (body [@tailcall]) ());
      Value.finish block
    in
    let cons = branch (fun () ->
      let element = Runtime.resume (fun () ->
        Value.get_method_id node Native_selectors.id_get_0 env []) in
      Dynarray.add_last values element;
      let next = Runtime.resume (fun () ->
        Value.get_method_id node Native_selectors.id_next_0 env []) in
      (loop [@tailcall]) next)
    in
    let nil = branch (fun () ->
      Builtins.minimal_list env (Dynarray.to_array values))
    in
    (* Church dispatch executes a branch, rather than inspecting a boolean. *)
    let chosen = Runtime.resume (fun () ->
      Value.get_method_id condition Native_selectors.id_then_else_2 env [cons; nil]) in
    let run = Value.get_method_id chosen Native_selectors.id_run_0 in
    (run [@tailcall]) env []
  in
  loop sequence

let make_core () =
  let extension = Value.uninitialized () in
  List.iter (fun kind ->
    Value.add_method extension kind 1 (fun _ args -> List.hd args))
    ["boolean"; "number"; "string"; "list"];
  Value.initialize extension;
  let core = Value.uninitialized () in
  Value.add_method_id core Native_selectors.id_extend_0 (fun _ _ -> extension);
  Value.add_method_id core Native_selectors.id_tag_1 (fun _ args ->
    let number = List.hd args |> Value.as_number in
    let tag = Value.uninitialized () in
    Value.set_number tag number;
    Value.finish tag);
  Value.add_method_id core Native_selectors.id_from_seq_1 (fun env args ->
    from_sequence env (List.hd args));
  Value.finish core

let box content =
  let content = ref content in
  let value = Value.uninitialized () in
  Value.add_method_id value Native_selectors.id_set_1 (fun _ args ->
    content := List.hd args;
    value);
  Value.add_method_id value Native_selectors.id_get_0 (fun _ _ -> !content);
  Value.finish value

let array () =
  let elements = Dynarray.create () in
  let value = Value.uninitialized () in
  let index arg =
    let i = Builtins.int_of_value arg in
    if i < 0 || i >= Dynarray.length elements then
      Runtime.error ("index out of bounds: " ^ string_of_int i);
    i
  in
  Value.add_method_id value Native_selectors.id_set_2 (fun _ args ->
    match args with
    | [i; element] ->
        Dynarray.set elements (index i) element;
        value
    | _ -> invalid_arg "wrong arity");
  Value.add_method_id value Native_selectors.id_at_1 (fun _ args ->
    Dynarray.get elements (index (List.hd args)));
  Value.add_method_id value Native_selectors.id_push_1 (fun _ args ->
    Dynarray.add_last elements (List.hd args);
    value);
  Value.add_method_id value Native_selectors.id_pop_0 (fun _ _ ->
    match Dynarray.pop_last_opt elements with
    | Some element -> element
    | None -> Runtime.error "attempt to pop empty array");
  Value.add_method_id value Native_selectors.id_size_0 (fun env _ ->
    Builtins.make_number env (float (Dynarray.length elements)));
  Value.finish value

let make ?(filename = "<string>") ?arguments ?(input = stdin) ?(output = stdout)
    ?(error = stderr) () =
  let value = Value.uninitialized () in
  let constant name capability =
    Value.add_method value name 0 (fun _ _ -> capability)
  in
  constant "io" (make_io ~input ~output ~error);
  constant "fs" (Filesystem.make ());
  let arguments = Option.value arguments ~default:[filename] in
  constant "system" (System.make ~arguments ());
  constant "utf-8" (Encoding.make ());
  constant "env" (environment_control ());
  constant "core" (make_core ());
  Value.add_method_id value Native_selectors.id_eval_1 (fun env args ->
    let source = List.hd args |> Builtins.string_of_value env in
    let filename = Diagnostics.filename env "<eval>" in
    let lowered =
      Lexer.create ~filename source |> Parser.parse |> Lowerer.lower
    in
    Evaluator.eval lowered.scope_size env lowered.ir);
  Value.add_method_id value Native_selectors.id_filename_0
    (fun env _ -> Builtins.make_byte_string env filename);
  Value.add_method_id value Native_selectors.id_box_1 (fun _ args -> box (List.hd args));
  Value.add_method_id value Native_selectors.id_array_0 (fun _ _ -> array ());
  Value.add_method_id value Native_selectors.id_true_0 (fun env _ -> Builtins.make_boolean env true);
  Value.add_method_id value Native_selectors.id_false_0 (fun env _ -> Builtins.make_boolean env false);
  Value.add_method_id value Native_selectors.id_crash_1 (fun env args ->
    List.hd args |> Builtins.string_of_value env |> Runtime.error);
  Value.finish value
