type t = {
  mutable number : float option;
  methods : storage;
  mutable initialized : bool;
}
and storage =
  | Table of (Selector.t, binding) Hashtbl.t
  | Numeric of number_layout * float
and binding =
  | Closure of (t -> t list -> t)
  | BoundNumber of number_code * float
and number_code = float -> t -> t list -> t
and number_layout = (Selector.t * number_code) array

let uninitialized () =
  { number = None; methods = Table (Hashtbl.create 16); initialized = false }

let set_number value number =
  assert (not value.initialized);
  value.number <- Some number

let ensure_initialized value =
  if not value.initialized then
    Runtime.error "attempt to call a method on an uninitialized object"

let as_number value =
  ensure_initialized value;
  match value.number with
  | Some n -> n
  | None -> Runtime.error "object has no numeric representation"

let table value = match value.methods with
  | Table table -> table
  | Numeric _ -> invalid_arg "cannot modify frozen numeric layout"

let add_method_id value selector body =
  assert (not value.initialized);
  Hashtbl.replace (table value) selector (Closure body)

let add_method value name arity body =
  add_method_id value (Selector.intern name arity) body

let iter_bindings f value = match value.methods with
  | Table table -> Hashtbl.iter f table
  | Numeric (layout, capture) ->
      Array.iter (fun (selector, code) ->
        f selector (BoundNumber (code, capture))) layout

let add_methods into from =
  assert (not into.initialized);
  ensure_initialized from;
  Option.iter (set_number into) from.number;
  iter_bindings (Hashtbl.replace (table into)) from

let missing selector =
  Runtime.error ("method " ^ Selector.describe selector ^ " not found")

let numeric_code layout selector =
  let rec search low high =
    if low > high then missing selector;
    let index = (low + high) / 2 in
    let key, code = layout.(index) in
    if key = selector then code
    else if key < selector then search (index + 1) high
    else search low (index - 1)
  in
  search 0 (Array.length layout - 1)

let apply binding env args = match binding with
  | Closure body -> (body [@tailcall]) env args
  | BoundNumber (code, capture) -> (code [@tailcall]) capture env args

let invoke_id value selector env args =
  ensure_initialized value;
  match value.methods with
  | Numeric (layout, capture) ->
      let code = numeric_code layout selector in
      (code [@tailcall]) capture env args
  | Table table ->
      match Hashtbl.find_opt table selector with
      | Some binding -> (apply [@tailcall]) binding env args
      | None -> missing selector

let get_method_id value selector =
  ensure_initialized value;
  match value.methods with
  | Numeric (layout, capture) ->
      let code = numeric_code layout selector in
      (fun env args -> (code [@tailcall]) capture env args)
  | Table table ->
      match Hashtbl.find_opt table selector with
      | Some (Closure body) -> body
      | Some binding -> (fun env args -> (apply [@tailcall]) binding env args)
      | None -> missing selector

let get_method value name arity =
  get_method_id value (Selector.intern name arity)

let create_number_layout methods =
  let layout = Array.copy methods in
  Array.sort (fun (a,_) (b,_) -> compare a b) layout;
  Array.iteri (fun i (selector,_) ->
    if i > 0 && fst layout.(i-1) = selector then
      invalid_arg "duplicate selector in numeric layout") layout;
  layout

let number_from_layout layout capture =
  { number = Some capture; methods = Numeric (layout, capture);
    initialized = true }

let initialize value = value.initialized <- true
let finish value = initialize value; value
let empty () = finish (uninitialized ())

let bind ?(before = fun () -> ()) env value =
  ensure_initialized value;
  let bound = uninitialized () in
  Option.iter (set_number bound) value.number;
  iter_bindings (fun key binding ->
    Hashtbl.replace (table bound) key
      (Closure (fun _ args -> before (); (apply [@tailcall]) binding env args)))
    value;
  finish bound

let to_string value =
  let names = ref [] in
  iter_bindings (fun selector _ ->
    names := Selector.describe selector :: !names) value;
  "{ " ^ Option.value ~default:"" (Option.map string_of_float value.number)
  ^ "; methods = [" ^ String.concat "; " !names ^ "]; "
  ^ (if value.initialized then "" else "not ") ^ "initialized }"
