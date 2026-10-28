type proof = Unknown | Argument of int | CapturedValue of int

let hooks = List.map (fun name -> Selector.intern name 1)
  ["number"; "boolean"; "string"; "list"]

(* Deliberately syntactic: no guesses about calls, construction, mutable
   contents, or the purity of an environment accessor. *)
let prove selector args body =
  if not (List.mem selector hooks) then Unknown else
  match body with
  | Ir.Captured index -> CapturedValue index
  | Ir.Variable slot ->
      let rec find position = function
        | [] -> Unknown
        | Some index :: _ when index = slot -> Argument position
        | _ :: rest -> find (position + 1) rest
      in
      find 0 args
  | _ -> Unknown
