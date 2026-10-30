let finish = Value.finish

let number_selector = Selector.intern "number" 1
let boolean_selector = Selector.intern "boolean" 1
let string_selector = Selector.intern "string" 1
let list_selector = Selector.intern "list" 1

let extend env kind value =
  let core = Value.get_method_id env Native_selectors.id_core_0 env [] in
  let extension = Value.get_method_id core Native_selectors.id_extend_0 env [] in
  let selector = match kind with
    | "number" -> number_selector
    | "boolean" -> boolean_selector
    | "string" -> string_selector
    | "list" -> list_selector
    | _ -> Selector.intern kind 1
  in
  Value.get_method_id extension selector env [value]

let arithmetic =
  List.map (fun (name, op) -> Selector.intern name 1, op)
    ["+", ( +. ); "-", ( -. ); "*", ( *. ); "/", ( /. );
     "mod", (fun a b ->
       let divisor = Float.abs b in
       let remainder = mod_float a divisor in
       if remainder < 0. then remainder +. divisor else remainder);
     "rem", mod_float; "^", Float.pow]

let comparisons =
  List.map (fun (name, op) -> Selector.intern name 1, op)
    ["=", ( = ); "<>", ( <> ); "<", ( < ); ">", ( > );
     "<=", ( <= ); ">=", ( >= )]

let rounding =
  List.map (fun (name, op) -> Selector.intern name 0, op)
    ["floor", Float.floor; "ceil", Float.ceil; "trunc", Float.trunc]

let expand_decimal text =
  match String.index_opt text 'e' with
  | None -> text
  | Some i ->
      let mantissa = String.sub text 0 i in
      let exponent =
        String.sub text (i + 1) (String.length text - i - 1) |> int_of_string
      in
      let point =
        Option.value (String.index_opt mantissa '.') ~default:(String.length
          mantissa)
      in
      let digits = String.concat "" (String.split_on_char '.' mantissa) in
      let point = point + exponent in
      if point <= 0 then "0." ^ String.make (-point) '0' ^ digits
      else if point >= String.length digits then
        digits ^ String.make (point - String.length digits) '0'
      else
        String.sub digits 0 point ^ "."
        ^ String.sub digits point (String.length digits - point)

let string_of_number number =
  if Float.is_nan number then "0nan"
  else if number = infinity then "0inf"
  else if number = neg_infinity then "0inf-"
  else
    let text = Printf.sprintf "%.17g" (Float.abs number) |> expand_decimal in
    let text =
      if String.ends_with ~suffix:"." text then
        String.sub text 0 (String.length text - 1)
      else text
    in
    if Float.sign_bit number then text ^ "-" else text

let int_of_value value =
  let n = Value.as_number value in
  if not (Float.is_integer n)
     || n < float min_int || n >= float max_int then
    Runtime.error ("expected a finite integer: " ^ string_of_number n);
  int_of_float n

let size_of_value env value =
  let result = Runtime.resume (fun () ->
    Value.get_method_id value Native_selectors.id_size_0 env []) in
  let size = int_of_value result in
  if size < 0 then Runtime.error ("invalid size " ^ string_of_int size);
  size

let make_boolean env bool =
  let value = Value.uninitialized () in
  Value.add_method_id value Native_selectors.id_then_else_2 (fun _ values ->
    match values with
    | [a; b] -> if bool then a else b
    | _ -> invalid_arg "wrong arity");
  extend env "boolean" (finish value)

let number_layout_cache = Atomic.make None
let number_layout_lock = Mutex.create ()

let rec make_number env number =
  Value.number_from_layout (get_number_layout ()) number
  |> extend env "number"

and get_number_layout () =
  match Atomic.get number_layout_cache with
  | Some layout -> layout
  | None ->
      Mutex.lock number_layout_lock;
      Fun.protect ~finally:(fun () -> Mutex.unlock number_layout_lock)
        (fun () -> match Atomic.get number_layout_cache with
          | Some layout -> layout
          | None ->
              (* Build only immutable code descriptors under the lock. No
                 guest code or extension hook runs until after publication. *)
              let layout = create_number_layout () in
              Atomic.set number_layout_cache (Some layout);
              layout)

and create_number_layout () =
  let binary = List.map (fun (selector, operation) ->
    selector, (fun number env args ->
      make_number env (operation number (Value.as_number (List.hd args)))))
    arithmetic in
  let compare = List.map (fun (selector, operation) ->
    selector, (fun number env args ->
      make_boolean env (operation number (Value.as_number (List.hd args)))))
    comparisons in
  let round = List.map (fun (selector, operation) ->
    selector, (fun number env _ -> make_number env (operation number)))
    rounding in
  let other = [
    Native_selectors.id_negate_0,
      (fun number env _ -> make_number env (-. number));
    Native_selectors.id_to_string_0,
      (fun number env _ -> make_string env (string_of_number number))
  ] in
  Value.create_number_layout (Array.of_list (binary @ compare @ round @ other))

and make_string env text =
  let codes = Dynarray.create () in
  let rec read i =
    if i < String.length text then (
      let decoded = String.get_utf_8_uchar text i in
      if not (Uchar.utf_decode_is_valid decoded) then
        invalid_arg ("invalid UTF-8 string at byte " ^ string_of_int i);
      let code = Uchar.utf_decode_uchar decoded |> Uchar.to_int in
      Dynarray.add_last codes code;
      read (i + Uchar.utf_decode_length decoded))
  in
  read 0;
  make_string_codes env (Dynarray.to_array codes)

and make_byte_string env text =
  make_string_codes env (Utf8.lossless text)

and make_string_codes env codes =
  let array = Array.map (fun code -> make_number env (float code)) codes in
  let size = make_number env (float (Array.length array)) in
  let value = Value.uninitialized () in
  Value.add_method_id value Native_selectors.id_at_1 (fun _ args ->
    let index = List.hd args |> int_of_value in
    if index < 0 || index >= Array.length array then
      Runtime.error ("index out of bounds: " ^ string_of_int index);
    array.(index));
  Value.add_method_id value Native_selectors.id_size_0 (fun _ _ -> size);
  extend env "string" (finish value)

let minimal_list env values =
  let array = values in
  let size = make_number env (float (Array.length array)) in
  let value = Value.uninitialized () in
  Value.add_method_id value Native_selectors.id_at_1 (fun _ args ->
    let index = List.hd args |> int_of_value in
    if index < 0 || index >= Array.length array then
      Runtime.error ("index out of bounds: " ^ string_of_int index);
    array.(index));
  Value.add_method_id value Native_selectors.id_size_0 (fun _ _ -> size);
  finish value

let make_list env values = extend env "list" (minimal_list env values)

let string_of_value ?(lossless = true) env value =
  let size = size_of_value env value in
  let at = Value.get_method_id value Native_selectors.id_at_1 env in
  let buffer = Buffer.create (min size 4096) in
  for i = 0 to size - 1 do
    let element = Runtime.resume (fun () ->
      at [make_number env (float i)]) in
    let code = int_of_value element in
    if lossless && code >= -255 && code < 0 then
      Buffer.add_char buffer (Char.chr (-code))
    else if Uchar.is_valid code then
      Buffer.add_utf_8_uchar buffer (Uchar.of_int code)
    else Runtime.error ("invalid character code " ^ string_of_int code)
  done;
  Buffer.contents buffer

let bytes_of_value env value =
  let size = size_of_value env value in
  let at = Value.get_method_id value Native_selectors.id_at_1 env in
  let bytes = Bytes.create size in
  for i = 0 to size - 1 do
    let element = Runtime.resume (fun () ->
      at [make_number env (float i)]) in
    let byte = int_of_value element in
    if byte < 0 || byte > 255 then
      Runtime.error ("invalid byte " ^ string_of_int byte);
    Bytes.set bytes i (Char.chr byte)
  done;
  bytes

let list_of_bytes env bytes =
  let values =
    Array.init (Bytes.length bytes)
      (fun i -> make_number env (float (Char.code (Bytes.get bytes i))))
  in
  make_list env values
