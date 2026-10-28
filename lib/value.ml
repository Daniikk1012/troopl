type t = {
  mutable number      : float option;
  methods             : (Selector.t, t -> t list -> t) Hashtbl.t;
  mutable initialized : bool;
}

let uninitialized () =
  { number = None; methods = Hashtbl.create 16; initialized = false }

let set_number value number =
  assert (not value.initialized);
  value.number <- Some number

let ensure_initialized value =
  if not value.initialized then
    Runtime.error "attempt to call a method on an uninitialized object"

let as_number value =
  if not value.initialized then
    Runtime.error
      "attempt to extract numeric representation of an uninitialized object";
  match value.number with
  | Some n -> n
  | None -> Runtime.error "object has no numeric representation"

let add_method_id value selector body =
  assert (not value.initialized);
  Hashtbl.replace value.methods selector body

let add_method value name arity body =
  add_method_id value (Selector.intern name arity) body

let add_methods into from =
  assert (not into.initialized);
  if not from.initialized then
    Runtime.error "attempt to include methods from an uninitialized object";
  Option.iter (set_number into) from.number;
  Hashtbl.iter (Hashtbl.replace into.methods) from.methods

let get_method_id value selector =
  ensure_initialized value;
  match Hashtbl.find_opt value.methods selector with
  | Some f -> f
  | None ->
      Runtime.error
        ("method " ^ Selector.describe selector ^ " not found")

let get_method value name arity =
  get_method_id value (Selector.intern name arity)

let initialize value = value.initialized <- true

let finish value = initialize value; value
let empty () = finish (uninitialized ())

let bind ?(before = fun () -> ()) env value =
  ensure_initialized value;
  let bound = uninitialized () in
  Option.iter (set_number bound) value.number;
  Hashtbl.iter
    (fun key body ->
      Hashtbl.replace bound.methods key
        (fun _ args -> before (); (body [@tailcall]) env args))
    value.methods;
  initialize bound;
  bound

let to_string value =
  "{ "
  ^ Option.value ~default:""
      (Option.map (fun s -> string_of_float s ^ "; ") value.number)
  ^ "methods = ["
  ^ (Hashtbl.to_seq_keys value.methods
    |> Seq.map Selector.describe |> List.of_seq
    |> String.concat "; ")
  ^ "]; " ^ (if value.initialized then "" else "not ") ^ "initialized }"
