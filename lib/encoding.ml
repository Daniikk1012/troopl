let remainder env source start =
  let view = Value.uninitialized () in
  Value.add_method view "size" 0 (fun env _ ->
    let size = Builtins.size_of_value env source in
    Builtins.make_number env (float (max 0 (size - start))));
  Value.add_method view "at" 1 (fun env args ->
    let index = List.hd args |> Builtins.int_of_value in
    let size = Builtins.size_of_value env source in
    if index < 0 || index >= size - start then
      Runtime.error ("index out of bounds: " ^ string_of_int index);
    let index = Builtins.make_number env (float (start + index)) in
    Value.get_method source "at" 1 env [index]);
  Builtins.extend env "list" (Value.finish view)

let make () =
  let utf8 = Value.uninitialized () in
  Value.add_method utf8 "from-string" 1 (fun env args ->
    List.hd args |> Builtins.string_of_value env |> Bytes.of_string
    |> Builtins.list_of_bytes env);
  Value.add_method utf8 "to-string" 1 (fun env args ->
    let source = List.hd args in
    let size = Builtins.size_of_value env source in
    let at = Value.get_method source "at" 1 env in
    let get index =
      let byte = Runtime.resume (fun () ->
        at [Builtins.make_number env (float index)]) in
      Builtins.int_of_value byte
    in
    let decoded = Utf8.decode ~size ~get in
    match decoded.invalid with
    | Some (index, byte, message) ->
        let fields = [
          "index", Builtins.make_number env (float index);
          "byte", Builtins.make_number env (float byte);
        ] in
        Outcome.failure ~fields env message
    | None ->
        let value = Value.uninitialized () in
        Value.add_methods value (Builtins.make_string env decoded.text);
        let suffix = remainder env source decoded.consumed in
        Value.add_method value "remainder" 0 (fun _ _ -> suffix);
        Outcome.success env (Value.finish value));
  Value.finish utf8
