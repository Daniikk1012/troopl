let string_of_value env value =
  let at   = Value.get_method value "at"   1 env in
  let size = Value.get_method value "size" 0 env [] |> Builtins.int_of_value in
  if size < 0 then
    raise (Runtime.Error (
      "invalid size " ^ Builtins.string_of_number (float size),
      Position.zero));
  let buf = Buffer.create 12 in
  for i = 0 to size - 1 do
    let n = at [Builtins.make_number env (float i)] |> Builtins.int_of_value in
    let u =
      try Uchar.of_int n with Invalid_argument _ -> raise (Runtime.Error (
        "invalid character code " ^ Builtins.string_of_number (float n),
        Position.zero))
    in
    Buffer.add_utf_8_uchar buf u
  done;
  Buffer.contents buf

let make_success env value =
  let value' = Value.uninitialized () in
  Value.add_methods value' value;
  let b = Builtins.make_boolean env true in
  Value.add_method value' "ok?" 0 (fun _ _ -> b);
  Value.initialize value';
  value

let make_failure env =
  let value = Value.uninitialized () in
  let b = Builtins.make_boolean env false in
  Value.add_method value "ok?" 0 (fun _ _ -> b);
  Value.initialize value;
  value

let io =
  let value = Value.uninitialized () in
  Value.add_method value "print" 1 (fun env values ->
    try
      List.hd values |> string_of_value env |> print_endline;
      make_success env value
    with Sys_error _ -> make_failure env);
  (* TODO: rest of io *)
  Value.initialize value;
  value

let env =
  let value = Value.uninitialized () in
  Value.add_method value "run" 2 (fun _ values ->
    match values with
    | [env; block] -> Value.get_method block "run" 0 env []
    | _ -> invalid_arg "wrong arity");
  Value.add_method value "bind" 2 (fun _ values ->
    match values with
    | [env; value] -> Value.bind env value
    | _ -> invalid_arg "wrong arity");
  Value.initialize value;
  value

let extend =
  let value = Value.uninitialized () in
  let id _ = List.hd in
  Value.add_method value "boolean" 1 id;
  Value.add_method value "number"  1 id;
  Value.add_method value "string"  1 id;
  Value.initialize value;
  value

let core =
  let value = Value.uninitialized () in
  Value.add_method value "extend" 0 (fun _ _ -> extend);
  Value.add_method value "tag" 1 (fun _ values ->
    let value = Value.uninitialized () in
    List.hd values |> Value.as_number |> Value.set_number value;
    value);
  (* TODO: from-seq *)
  Value.initialize value;
  value

let default =
  let value = Value.uninitialized () in
  Value.add_method value "io"  0 (fun _ _ -> io);
  (* TODO: fs *)
  Value.add_method value "env" 0 (fun _ _ -> env);
  Value.add_method value "eval" 1 (fun env values ->
    let lowered =
      List.hd values |> string_of_value env |> Lexer.create |> Parser.parse
      |> Lowerer.lower
    in
    Evaluator.eval lowered.scope_size env lowered.ir);
  Value.add_method value "box" 1 (fun _ values ->
    let box = List.hd values |> ref in
    let value = Value.uninitialized () in
    Value.add_method value "set" 1
      (fun _ values -> box := List.hd values; value);
    Value.add_method value "get" 0 (fun _ _ -> !box);
    Value.initialize value;
    value);
  Value.add_method value "array" 0 (fun _ _ ->
    let array = Dynarray.create () in
    let value = Value.uninitialized () in
    Value.add_method value "set" 2 (fun _ values ->
      match values with
      | [index; value] ->
          let n = Builtins.int_of_value index in
          if n < 0 || n >= Dynarray.length array then raise (Runtime.Error (
            "index out of bounds " ^ Builtins.string_of_number (float n),
            Position.zero));
          Dynarray.set array n value;
          value
      | _ -> invalid_arg "wrong arity");
    Value.add_method value "at" 1 (fun _ values ->
      let n = List.hd values |> Builtins.int_of_value in
      if n < 0 || n >= Dynarray.length array then raise (Runtime.Error (
        "index out of bounds " ^ Builtins.string_of_number (float n),
        Position.zero));
      Dynarray.get array n);
    Value.add_method value "push" 1 (fun _ values ->
      List.hd values |> Dynarray.add_last array;
      value);
    Value.add_method value "pop" 0 (fun _ _ ->
      match Dynarray.pop_last_opt array with
      | Some value -> value
      | None ->
          raise (Runtime.Error ("attempt to pop empty array", Position.zero)));
    Value.add_method value "size" 0
      (fun env _ -> Dynarray.length array |> float |> Builtins.make_number env);
    Value.initialize value;
    value);
  Value.add_method value "true"  0 (fun env _ -> Builtins.make_boolean env true);
  Value.add_method value "false" 0
    (fun env _ -> Builtins.make_boolean env false);
  Value.add_method value "core"  0 (fun _ _ -> core);
  Value.add_method value "exit" 1 (fun _ values ->
    List.hd values |> Builtins.int_of_value |> exit);
  Value.add_method value "crash" 1 (fun env values -> raise
    (Runtime.Error (List.hd values |> string_of_value env, Position.zero)));
  Value.initialize value;
  value
