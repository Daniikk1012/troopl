let rec eval_ir scope env : Ir.t -> _ = function
  | Definition { index; value; scope = rest } ->
      scope.(index) <- Some (eval_ir scope env value);
      (eval_ir [@tailcall]) scope env rest
  | RecursiveDefinition { index; entries; scope = rest } ->
      let value = Value.uninitialized () in
      scope.(index) <- Some value;
      fill_with_entries env scope value entries;
      (eval_ir [@tailcall]) scope env rest
  | Object entries ->
      let value = Value.uninitialized () in
      fill_with_entries env scope value entries;
      value
  | Sequence (a, b) ->
      ignore (eval_ir scope env a);
      (eval_ir [@tailcall]) scope env b
  | Variable i ->
      (match scope.(i) with
       | Some value -> value
       | None -> Runtime.error "uninitialized variable slot")
  | Number (n, pos) -> Builtins.locate env pos; Builtins.make_number env n
  | String (s, pos) -> Builtins.locate env pos; Builtins.make_string env s
  | Environment -> env
  | Call { value; name; args; pos } ->
      let value = eval_ir scope env value in
      Builtins.locate env pos;
      (* Validate before evaluating arguments, as required by section 5.9. *)
      Value.ensure_initialized value;
      let args = List.map (eval_ir scope env) args in
      Builtins.locate env pos;
      let method_ = Value.get_method value name (List.length args) in
      (method_ [@tailcall]) env args

and fill_with_entries env scope value entries =
  List.iter
    (function
    | Ir.Method { name; args; body; captures; scope_size } ->
        let run env values =
          let scope' = Array.make scope_size None in
          List.iter2
            (fun v i -> Option.iter (fun i -> scope'.(i) <- Some v) i)
            values args;
          List.iter
            (fun (c : Ir.capture) -> scope'.(c.inner) <- scope.(c.outer))
            captures;
          (eval_ir [@tailcall]) scope' env body
        in
        Value.add_method value name (List.length args) run
    | Inclusion { value = inclusion; pos } ->
        let inclusion = eval_ir scope env inclusion in
        Builtins.locate env pos;
        Value.add_methods value inclusion)
    entries;
  Value.initialize value

let eval scope_size env ir =
  Runtime.protect (fun () ->
    Builtins.locate env Position.zero;
    eval_ir (Array.make scope_size None) env ir)
