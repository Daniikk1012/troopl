(* Second lowering pass: split local slots from closure captures. A child
   whose free values all live in its parent's capture array reuses that array
   and addresses the original indices directly, including subset/reordering. *)
let local mapping index = match mapping.(index) with
  | Ir.Local index -> index
  | Ir.Capture _ -> invalid_arg "definition or argument in capture slot"

let rec expression mapping : Ir.t -> Ir.t = function
  | Variable index ->
      (match mapping.(index) with
       | Ir.Local i -> Variable i
       | Ir.Capture i -> Captured i)
  | Definition { index; value; scope } ->
      Definition { index = local mapping index;
        value = expression mapping value; scope = expression mapping scope }
  | RecursiveDefinition { index; entries; scope } ->
      RecursiveDefinition { index = local mapping index;
        entries = List.map (entry mapping) entries;
        scope = expression mapping scope }
  | Sequence (a, b) -> Sequence (expression mapping a, expression mapping b)
  | Object entries -> Object (List.map (entry mapping) entries)
  | Call call ->
      Call { call with value = expression mapping call.value;
        args = List.map (expression mapping) call.args }
  | (Captured _ | Number _ | String _ | Environment) as value -> value

and entry mapping : Ir.entry -> Ir.entry = function
  | Inclusion inclusion ->
      Inclusion { inclusion with value = expression mapping inclusion.value }
  | CompiledMethod _ -> invalid_arg "method lowered twice"
  | Method { name; args; body; captures; scope_size } ->
      let sources = Array.of_list (List.map
        (fun (capture : Ir.capture) -> mapping.(capture.outer)) captures) in
      let plan =
        if Array.length sources = 0 then Ir.NoCaptures
        else if Array.for_all (function Ir.Capture _ -> true | _ -> false)
            sources then Ir.ReuseCaptures
        else Ir.CaptureValues sources
      in
      let child = Array.make scope_size (Ir.Local (-1)) in
      List.iteri (fun index (capture : Ir.capture) ->
        let index = match plan, sources.(index) with
          | Ir.ReuseCaptures, Ir.Capture index -> index
          | _ -> index
        in
        child.(capture.inner) <- Ir.Capture index) captures;
      let next = ref 0 in
      Array.iteri (fun index address -> match address with
        | Ir.Capture _ -> ()
        | Ir.Local _ ->
            child.(index) <- Ir.Local !next;
            incr next) child;
      let args = List.map (Option.map (local child)) args in
      CompiledMethod { selector = Selector.intern name (List.length args);
        args; body = expression child body; plan; scope_size = !next }

let lower scope_size ir =
  expression (Array.init scope_size (fun i -> Ir.Local i)) ir
