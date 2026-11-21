(* Unassigned frame slots hold this sentinel instead of [None], so binding a
   definition or argument does not allocate an option. *)
let unset = Value.uninitialized ()

let read value =
  if value == unset then invalid_arg "uninitialized variable slot" else value

let location locals captured = function
  | Ir.Local i -> locals.(i)
  | Ir.Capture i -> captured.(i)

let rec bind_args locals values (args : int option list) =
  match (values, args) with
  | value :: values, Some index :: args ->
      locals.(index) <- value;
      bind_args locals values args
  | _ :: values, None :: args -> bind_args locals values args
  | [], [] -> ()
  | _ -> invalid_arg "wrong arity"

let rec eval_ir locals captured env : Ir.t -> _ = function
  | Definition { index; value; scope = rest } ->
      locals.(index) <- eval_ir locals captured env value;
      (eval_ir [@tailcall]) locals captured env rest
  | RecursiveDefinition { index; entries; scope = rest } ->
      let value = Value.uninitialized () in
      locals.(index) <- value;
      fill_with_entries env locals captured value entries;
      (eval_ir [@tailcall]) locals captured env rest
  | Object entries ->
      let value = Value.uninitialized () in
      fill_with_entries env locals captured value entries;
      value
  | Sequence (a, b) ->
      ignore (eval_ir locals captured env a);
      (eval_ir [@tailcall]) locals captured env b
  | Variable i -> read locals.(i)
  | Captured i -> read captured.(i)
  | Number (n, pos) ->
      Diagnostics.locate env pos;
      Builtins.make_number env n
  | String (s, pos) ->
      Diagnostics.locate env pos;
      Builtins.make_string env s
  | Text (codes, pos) ->
      Diagnostics.locate env pos;
      Value.make_string_codes env codes
  | Environment -> env
  | Call { value; selector; args; pos; _ } ->
      let value = eval_ir locals captured env value in
      Diagnostics.locate env pos;
      Value.ensure_initialized value;
      let args = List.map (eval_ir locals captured env) args in
      Diagnostics.locate env pos;
      (Value.invoke_checked [@tailcall]) value selector env args

(* This factory receives capture values, never the parent's local frame.
   A zero-capture method cannot accidentally retain that frame. *)
and make_method captured args scope_size body env values =
  let locals = if scope_size = 0 then [||] else Array.make scope_size unset in
  bind_args locals values args;
  (eval_ir [@tailcall]) locals captured env body

and fill_with_entries env locals captured value entries =
  List.iter
    (function
      | Ir.CompiledMethod { selector; args; body; plan; scope_size } ->
          let captures =
            match plan with
            | Ir.ReuseCaptures -> captured
            | Ir.CaptureValues sources ->
                Array.map (location locals captured) sources
          in
          let run = make_method captures args scope_size body in
          Value.add_method_id value selector run
      | Ir.Method { name; args; body; captures; scope_size } ->
          (* Reference path for lower ~optimize:false and differential tests. *)
          let run env values =
            let frame = Array.make scope_size unset in
            bind_args frame values args;
            List.iter
              (fun (c : Ir.capture) -> frame.(c.inner) <- locals.(c.outer))
              captures;
            (eval_ir [@tailcall]) frame [||] env body
          in
          Value.add_method value name (List.length args) run
      | Ir.Inclusion { value = inclusion; pos } ->
          let inclusion = eval_ir locals captured env inclusion in
          Diagnostics.locate env pos;
          Value.add_methods value inclusion)
    entries;
  Value.initialize value

let eval scope_size env ir =
  Runtime.protect (fun () ->
      Diagnostics.locate env Position.zero;
      try eval_ir (Array.make scope_size unset) [||] env ir
      with Stack_overflow ->
        (* Reported at the last located call, before [protect] restores the
           caller's location. The innermost [eval] on the stack reports it. *)
        Runtime.error "stack overflow: recursion is too deep")
