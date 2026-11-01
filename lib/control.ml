let run env block =
  let body = Value.get_method block "run" 0 in
  (body [@tailcall]) env []

let escape env body =
  let exception Exit of Value.t in
  let live = ref true in
  let domain = Domain.self () and thread = Thread.id (Thread.self ()) in
  let exit = Value.uninitialized () in
  Value.add_method exit "return" 1 (fun _ values ->
    if Domain.self () <> domain || Thread.id (Thread.self ()) <> thread then
      Runtime.error "escape belongs to another execution context";
    if not !live then Runtime.error "escape is no longer active";
    raise (Exit (List.hd values)));
  Value.initialize exit;
  Runtime.resume (fun () ->
    Fun.protect ~finally:(fun () -> live := false) (fun () ->
      let invoke = Value.get_method body "run" 1 in
      try invoke env [exit] with Exit value -> value))

let ensure env body cleanup =
  let position = Runtime.position () in
  Runtime.resume (fun () ->
    let outcome =
      try Ok (run env body) with error ->
        Error (error, Printexc.get_raw_backtrace ())
    in
    Diagnostics.locate env position;
    let cleanup_error =
      try ignore (run env cleanup); None with error ->
        Some (error, Printexc.get_raw_backtrace ())
    in
    match outcome, cleanup_error with
    | Error (error, trace), _ ->
        Printexc.raise_with_backtrace error trace
    | Ok _, Some (error, trace) ->
        Printexc.raise_with_backtrace error trace
    | Ok value, None -> value)

let make () =
  let result = Value.uninitialized () in
  Value.add_method result "escape" 1 (fun env args ->
    escape env (List.hd args));
  Value.add_method result "ensure" 2 (fun env args ->
    match args with
    | [body; cleanup] -> ensure env body cleanup
    | _ -> invalid_arg "wrong arity");
  Value.finish result

let extend env =
  let result = Value.uninitialized () in
  Value.add_methods result env;
  let control = make () in
  Value.add_method result "control" 0 (fun _ _ -> control);
  Value.finish result
