type t = {
  mutable number      : float option;
  methods             : (string * int, t -> t list -> t) Hashtbl.t;
  mutable initialized : bool;
}

let uninitialized () =
  { number = None; methods = Hashtbl.create 12; initialized = false }

let set_number value number = value.number <- Some number

let as_number value =
  if not value.initialized then
    raise (Runtime.Error (
      "attempt to extract numeric representation of an uninitialized object",
      Position.zero));
  match value.number with
  | Some n -> n
  | None -> raise
      (Runtime.Error ("object has no numeric representation", Position.zero))

let add_method value name arity body =
  assert (not value.initialized);
  Hashtbl.replace value.methods (name, arity) body

let add_methods into from =
  assert (not into.initialized);
  if not from.initialized then
    raise (Runtime.Error (
      "attempt to include methods from an uninitialized object",
      Position.zero));
  Option.iter (set_number into) from.number;
  Hashtbl.iter (Hashtbl.replace into.methods) from.methods

let get_method value name arity =
  if not value.initialized then
    raise (Runtime.Error
      ("attempt to call a method on an uninitialized object", Position.zero));
  match Hashtbl.find_opt value.methods (name, arity) with
  | Some f -> f
  | None -> raise (Runtime.Error (
      "method " ^ name ^ "/" ^ string_of_int arity ^ " not found",
      Position.zero))

let initialize value = value.initialized <- true

let to_string value =
  "{ "
  ^ Option.value ~default:""
      (Option.map (fun s -> string_of_float s ^ "; ") value.number)
  ^ "methods = ["
  ^ (Hashtbl.to_seq_keys value.methods
    |> Seq.map (fun (s, n) -> s ^ "/" ^ string_of_int n) |> List.of_seq
    |> String.concat "; ")
  ^ "]; " ^ (if value.initialized then "" else "not ") ^ "initialized }"
