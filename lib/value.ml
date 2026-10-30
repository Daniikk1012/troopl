type t = {
  mutable number : float option;
  mutable methods : storage;
  mutable initialized : bool;
}
and storage =
  | Empty
  | Table of (Selector.t, callable) Hashtbl.t
  | Numeric of number_layout * float
  | Shared of storage * int
  | Overlay of (Selector.t, callable) Hashtbl.t * storage * int
  | Merge of storage * storage * int
  | Bound of storage * t * (unit -> unit) * int
and callable = t -> t list -> t
and number_code = float -> t -> t list -> t
and number_layout = (Selector.t * number_code) array

let uninitialized () =
  { number = None; methods = Empty; initialized = false }

let set_number value number =
  assert (not value.initialized);
  value.number <- Some number

let ensure_initialized value =
  if not value.initialized then
    Runtime.error "attempt to call a method on an uninitialized object"

let as_number value =
  if not value.initialized then
    Runtime.error "attempt to read an uninitialized object";
  match value.number with
  | Some n -> n
  | None -> Runtime.error "object has no numeric representation"

let missing selector =
  Runtime.error ("method " ^ Selector.describe selector ^ " not found")

(* No per-lookup search closure. Layouts are sorted once when published. *)
let rec numeric_index (layout : number_layout) (selector : Selector.t) low high =
  if low > high then -1 else
  let index = (low + high) / 2 in
  let key, _ = layout.(index) in
  if key = selector then index
  else if key < selector then
    (numeric_index [@tailcall]) layout selector (index + 1) high
  else (numeric_index [@tailcall]) layout selector low (index - 1)

let numeric_code layout selector =
  let index = numeric_index layout selector 0 (Array.length layout - 1) in
  if index < 0 then missing selector;
  snd layout.(index)

let depth = function
  | Empty -> 0
  | Table _ | Numeric _ -> 1
  | Shared (_, depth) | Overlay (_, _, depth) | Merge (_, _, depth)
  | Bound (_, _, _, depth) -> depth

let rec contains storage selector = match storage with
  | Empty -> false
  | Table table -> Hashtbl.mem table selector
  | Numeric (layout, _) ->
      numeric_index layout selector 0 (Array.length layout - 1) >= 0
  | Shared (base, _) | Bound (base, _, _, _) ->
      (contains [@tailcall]) base selector
  | Overlay (delta, base, _) ->
      Hashtbl.mem delta selector || (contains [@tailcall]) base selector
  | Merge (later, earlier, _) ->
      contains later selector || (contains [@tailcall]) earlier selector

(* Resolving a binding captures only its lexical payload/environment, never
   the whole overlay chain. Flattening can therefore release hidden methods. *)
let rec resolve storage selector = match storage with
  | Empty -> missing selector
  | Table table ->
      (try Hashtbl.find table selector with Not_found -> missing selector)
  | Numeric (layout, capture) ->
      let code = numeric_code layout selector in
      (fun env args -> (code [@tailcall]) capture env args)
  | Shared (base, _) -> (resolve [@tailcall]) base selector
  | Overlay (delta, base, _) ->
      (match Hashtbl.find delta selector with
       | body -> body
       | exception Not_found -> (resolve [@tailcall]) base selector)
  | Merge (later, earlier, _) ->
      (resolve [@tailcall])
        (if contains later selector then later else earlier) selector
  | Bound (base, env, before, _) ->
      let body = resolve base selector in
      (fun _ args -> before (); (body [@tailcall]) env args)

let rec iter_selectors f = function
  | Empty -> ()
  | Table table -> Hashtbl.iter (fun selector _ -> f selector) table
  | Numeric (layout, _) -> Array.iter (fun (selector, _) -> f selector) layout
  | Shared (base, _) | Bound (base, _, _, _) -> iter_selectors f base
  | Overlay (delta, base, _) ->
      iter_selectors f base;
      Hashtbl.iter (fun selector _ -> f selector) delta
  | Merge (later, earlier, _) ->
      iter_selectors f earlier;
      iter_selectors f later

(* Limit both lookup depth and the lifetime of overridden capture groups.
   Only completed objects are shared. An object's current Table/Overlay delta
   is owned until the next inclusion freezes it under Shared/Merge. *)
let max_depth = 8

let bounded storage =
  if depth storage <= max_depth then storage else
  let table = Hashtbl.create 16 in
  iter_selectors (fun selector ->
    if not (Hashtbl.mem table selector) then
      Hashtbl.add table selector (resolve storage selector)) storage;
  Table table

let add_method_id value selector body =
  assert (not value.initialized);
  match value.methods with
  | Table table | Overlay (table, _, _) -> Hashtbl.replace table selector body
  | base ->
      let table = Hashtbl.create 16 in
      Hashtbl.add table selector body;
      value.methods <- bounded (match base with
        | Empty -> Table table
        | _ -> Overlay (table, base, depth base + 1))

let add_method value name arity body =
  add_method_id value (Selector.intern name arity) body

let add_methods into from =
  assert (not into.initialized);
  ensure_initialized from;
  Option.iter (set_number into) from.number;
  match from.methods, into.methods with
  | Empty, _ -> ()
  | source, Empty -> into.methods <- bounded (Shared (source, depth source + 1))
  | source, previous ->
      into.methods <- bounded
        (Merge (source, previous, 1 + max (depth source) (depth previous)))

let rec invoke storage selector env args = match storage with
  | Empty -> missing selector
  | Table table ->
      let body = try Hashtbl.find table selector
        with Not_found -> missing selector in
      (body [@tailcall]) env args
  | Numeric (layout, capture) ->
      let code = numeric_code layout selector in
      (code [@tailcall]) capture env args
  | Shared (base, _) -> (invoke [@tailcall]) base selector env args
  | Overlay (delta, base, _) ->
      (match Hashtbl.find delta selector with
       | body -> (body [@tailcall]) env args
       | exception Not_found -> (invoke [@tailcall]) base selector env args)
  | Merge (later, earlier, _) ->
      (invoke [@tailcall])
        (if contains later selector then later else earlier) selector env args
  | Bound (base, bound_env, before, _) ->
      (* Missing methods must fail before the diagnostic/environment callback. *)
      if not (contains base selector) then missing selector;
      before ();
      (invoke [@tailcall]) base selector bound_env args

let invoke_id value selector env args =
  ensure_initialized value;
  (invoke [@tailcall]) value.methods selector env args

let get_method_id value selector =
  ensure_initialized value;
  resolve value.methods selector

let get_method value name arity =
  get_method_id value (Selector.intern name arity)

let create_number_layout methods =
  let layout = Array.copy methods in
  Array.sort (fun (a, _) (b, _) -> compare a b) layout;
  Array.iteri (fun i (selector, _) ->
    if i > 0 && fst layout.(i - 1) = selector then
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
  { number = value.number; initialized = true;
    methods = bounded (Bound (value.methods, env, before, depth value.methods + 1)) }

let storage_depth value = depth value.methods

let to_string value =
  let selectors = Hashtbl.create 16 in
  iter_selectors (fun selector -> Hashtbl.replace selectors selector ())
    value.methods;
  let names = Hashtbl.fold (fun selector () names ->
    Selector.describe selector :: names) selectors [] in
  "{ " ^ Option.value ~default:"" (Option.map string_of_float value.number)
  ^ "; methods = [" ^ String.concat "; " names ^ "]; "
  ^ (if value.initialized then "" else "not ") ^ "initialized }"
