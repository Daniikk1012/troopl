let filename env fallback =
  try
    Value.get_method_id env Native_selectors.id_filename_0 env []
    |> Builtins.string_of_value env
  with _ -> fallback

(* The environment is recorded, not a closure over it; [filename] runs only
   when an error is reported. *)
let set_environment env = Runtime.set_environment env filename
let locate env position = Runtime.set_location position env filename
