let filename env fallback =
  try
    Value.get_method env "filename" 0 env [] |> Builtins.string_of_value env
  with _ -> fallback

let set_environment env =
  let fallback =
    Option.value (Runtime.position ()).filename ~default:"<unknown>"
  in
  Runtime.set_environment (fun () -> filename env fallback)

let locate env position =
  let fallback = Option.value position.Position.filename ~default:"<unknown>" in
  Runtime.set_location position (fun () -> filename env fallback)
