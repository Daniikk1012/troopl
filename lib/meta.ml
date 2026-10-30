let arity value =
  let count = Builtins.int_of_value value in
  if count < 0 then Runtime.error "method arity must be nonnegative";
  count

let arguments env source =
  let count = Builtins.size_of_value env source in
  let at = Value.get_method source "at" 1 in
  List.init count (fun index -> Runtime.resume (fun () ->
    at env [Builtins.make_number env (float index)]))

let new_method selector count source =
  Value.ensure_initialized source;
  let body = Value.get_method source "run" count in
  let result = Value.uninitialized () in
  Value.add_method_id result selector body;
  Value.finish result

let make () =
  let capability = Value.uninitialized () in
  Value.add_method capability "new-method" 3 (fun env values ->
    match values with
    | [name; count; source] ->
        let name = Builtins.string_of_value env name in
        let count = arity count in
        new_method (Selector.intern name count) count source
    | _ -> invalid_arg "wrong arity");
  Value.add_method capability "invoke" 3 (fun env values ->
    match values with
    | [target; name; source] ->
        Value.ensure_initialized target;
        let name = Builtins.string_of_value env name in
        let values = arguments env source in
        let body = Value.get_method target name (List.length values) in
        (body [@tailcall]) env values
    | _ -> invalid_arg "wrong arity");
  Value.finish capability

let extend env =
  let result = Value.uninitialized () in
  Value.add_methods result env;
  let meta = make () in
  Value.add_method result "meta" 0 (fun _ _ -> meta);
  Value.finish result
