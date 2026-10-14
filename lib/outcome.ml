(** Recoverable capability failures are values, never guest exceptions. *)

let success env source =
  let result = Value.uninitialized () in
  Value.add_methods result source;
  let yes = Builtins.make_boolean env true in
  Value.add_method result "ok?" 0 (fun _ _ -> yes);
  Value.finish result

let failure ?(fields = []) env message =
  let result = Value.uninitialized () in
  let no = Builtins.make_boolean env false in
  let message = Builtins.make_string env message in
  Value.add_method result "ok?" 0 (fun _ _ -> no);
  Value.add_method result "message" 0 (fun _ _ -> message);
  List.iter (fun (name, value) ->
    Value.add_method result name 0 (fun _ _ -> value)) fields;
  Value.finish result

let attempt env f =
  try success env (f ()) with Sys_error message -> failure env message
