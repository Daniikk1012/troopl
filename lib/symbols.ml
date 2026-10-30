let brand = Selector.fresh "<symbol-brand>" 0

let identity value =
  Value.ensure_initialized value;
  match Value.find_method_id value brand with
  | None -> Runtime.error "expected a symbol capability"
  | Some get -> get value []

let new_key () =
  let marker = Value.empty () in
  let family = Hashtbl.create 4 and lock = Mutex.create () in
  let selector count =
    Mutex.lock lock;
    Fun.protect ~finally:(fun () -> Mutex.unlock lock) (fun () ->
      match Hashtbl.find_opt family count with
      | Some id -> id
      | None ->
          let id = Selector.fresh "<private>" count in
          Hashtbl.add family count id;
          id)
  in
  let key = Value.uninitialized () in
  Value.add_method_id key brand (fun _ _ -> marker);
  Value.add_method key "new-method" 2 (fun _ values ->
    match values with
    | [count; source] ->
        let count = Meta.arity count in
        Meta.new_method (selector count) count source
    | _ -> invalid_arg "wrong arity");
  Value.add_method key "invoke" 2 (fun env values ->
    match values with
    | [target; source] ->
        Value.ensure_initialized target;
        let args = Meta.arguments env source in
        let body = Value.get_method_id target (selector (List.length args)) in
        (body [@tailcall]) env args
    | _ -> invalid_arg "wrong arity");
  Value.add_method key "run" 2 (fun _ values ->
    match values with
    | [count; target] ->
        let count = Meta.arity count in
        let body = Value.get_method_id target (selector count) in
        let result = Value.uninitialized () in
        Value.add_method result "run" count body;
        Value.finish result
    | _ -> invalid_arg "wrong arity");
  Value.finish key

let make () =
  let result = Value.uninitialized () in
  Value.add_method result "new" 0 (fun _ _ -> new_key ());
  Value.add_method result "equal?" 2 (fun env values ->
    match values with
    | [a;b] -> Builtins.make_boolean env (identity a == identity b)
    | _ -> invalid_arg "wrong arity");
  List.iter (fun operation ->
    Value.add_method result operation 3 (fun env values ->
      match values with
      | [key; count; source] ->
          ignore (identity key);
          let body = Value.get_method key operation 2 in
          (body [@tailcall]) env [count;source]
      | _ -> invalid_arg "wrong arity")) ["new-method";"run"];
  Value.finish result

let extend env =
  let result = Value.uninitialized () in
  Value.add_methods result env;
  let symbol = make () in
  Value.add_method result "symbol" 0 (fun _ _ -> symbol);
  Value.finish result
