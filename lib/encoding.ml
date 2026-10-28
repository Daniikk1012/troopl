let make () =
  let utf8 = Value.uninitialized () in
  Value.add_method_id utf8 Native_selectors.id_to_bytes_1 (fun env args ->
    List.hd args |> Builtins.string_of_value env |> Bytes.of_string
    |> Builtins.list_of_bytes env);
  Value.add_method_id utf8 Native_selectors.id_from_bytes_1 (fun env args ->
    List.hd args |> Builtins.bytes_of_value env |> Bytes.to_string
    |> Builtins.make_byte_string env);
  Value.finish utf8
