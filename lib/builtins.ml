let finish value = Value.initialize value; value

let extend env kind value =
  let core = Value.get_method env "core" 0 env [] in
  let extension = Value.get_method core "extend" 0 env [] in
  Value.get_method extension kind 1 env [value]

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
  if Float.is_nan number then "NaN"
  else if number = infinity then "Infinity"
  else if number = neg_infinity then "Infinity-"
  else
    let text = Printf.sprintf "%.17g" (Float.abs number) |> expand_decimal in
    let text =
      if String.ends_with ~suffix:"." text then
        String.sub text 0 (String.length text - 1)
      else text
    in
    if number < 0. then text ^ "-" else text

let int_of_value value =
  let n = Value.as_number value in
  if not (Float.is_finite n && Float.is_integer n)
     || n < float min_int || n >= float max_int then
    Runtime.error ("expected a finite integer: " ^ string_of_number n);
  int_of_float n

let size_of_value env value =
  let result = Runtime.resume (fun () ->
    Value.get_method value "size" 0 env []) in
  let size = int_of_value result in
  if size < 0 then Runtime.error ("invalid size " ^ string_of_int size);
  size

let make_boolean env bool =
  let value = Value.uninitialized () in
  Value.add_method value "then-else" 2 (fun _ values ->
    match values with
    | [a; b] -> if bool then a else b
    | _ -> invalid_arg "wrong arity");
  extend env "boolean" (finish value)

let rec make_number env number =
  let value = Value.uninitialized () in
  Value.set_number value number;
  List.iter (fun (name, operation) ->
    Value.add_method value name 1 (fun env values ->
      operation number (List.hd values |> Value.as_number)
      |> make_number env))
    ["+", ( +. ); "-", ( -. ); "*", ( *. ); "/", ( /. );
     "mod", (fun a b ->
       let divisor = Float.abs b in
       let remainder = mod_float a divisor in
       if remainder < 0. then remainder +. divisor else remainder);
     "rem", mod_float; "^", Float.pow];
  Value.add_method value "-" 0 (fun env _ -> make_number env (-. number));
  List.iter (fun (name, compare) ->
    Value.add_method value name 1 (fun env values ->
      compare number (List.hd values |> Value.as_number) |> make_boolean env))
    ["=", ( = ); "<>", ( <> ); "<", ( < ); ">", ( > );
     "<=", ( <= ); ">=", ( >= )];
  List.iter (fun (name, operation) ->
    Value.add_method value name 0
      (fun env _ -> operation number |> make_number env);
    (* Section 6.2 also documents these as operations on an argument. *)
    Value.add_method value name 1 (fun env values ->
      operation (List.hd values |> Value.as_number) |> make_number env))
    ["floor", Float.floor; "ceil", Float.ceil; "trunc", Float.trunc];
  Value.add_method value "to-string" 0
    (fun env _ -> make_string env (string_of_number number));
  extend env "number" (finish value)

and make_string env text =
  let values = Dynarray.create () in
  let rec read i =
    if i < String.length text then (
      let decoded = String.get_utf_8_uchar text i in
      if not (Uchar.utf_decode_is_valid decoded) then
        Runtime.error ("invalid UTF-8 string at byte " ^ string_of_int i);
      let code = Uchar.utf_decode_uchar decoded |> Uchar.to_int in
      Dynarray.add_last values (make_number env (float code));
      read (i + Uchar.utf_decode_length decoded))
  in
  read 0;
  let array = Dynarray.to_array values in
  let size = make_number env (float (Array.length array)) in
  let value = Value.uninitialized () in
  Value.add_method value "at" 1 (fun _ args ->
    let index = List.hd args |> int_of_value in
    if index < 0 || index >= Array.length array then
      Runtime.error ("index out of bounds: " ^ string_of_int index);
    array.(index));
  Value.add_method value "size" 0 (fun _ _ -> size);
  extend env "string" (finish value)

let make_list env values =
  let array = Array.copy values in
  let size = make_number env (float (Array.length array)) in
  let value = Value.uninitialized () in
  Value.add_method value "at" 1 (fun _ args ->
    let index = List.hd args |> int_of_value in
    if index < 0 || index >= Array.length array then
      Runtime.error ("index out of bounds: " ^ string_of_int index);
    array.(index));
  Value.add_method value "size" 0 (fun _ _ -> size);
  extend env "list" (finish value)

let read_string env value index_value =
  let size = size_of_value env value in
  let at = Value.get_method value "at" 1 env in
  let buffer = Buffer.create (min size 4096) in
  for i = 0 to size - 1 do
    let element = Runtime.resume (fun () ->
      at [index_value i]) in
    let code = int_of_value element in
    if not (Uchar.is_valid code) then
      Runtime.error ("invalid character code " ^ string_of_int code);
    Buffer.add_utf_8_uchar buffer (Uchar.of_int code)
  done;
  Buffer.contents buffer

let string_of_value env value =
  read_string env value (fun i -> make_number env (float i))

let filename env fallback =
  try
    let value = Value.get_method env "filename" 0 env [] in
    try string_of_value env value with _ ->
      (* Diagnostics must still read a captured filename when core is absent.
         These internal indices are bare numeric tags, not guest literals. *)
      read_string env value (fun i ->
        let tag = Value.uninitialized () in
        Value.set_number tag (float i);
        finish tag)
  with _ -> fallback

let set_environment env =
  let fallback =
    Option.value (Runtime.current ()).position.filename ~default:"<unknown>"
  in
  Runtime.set_environment (fun () -> filename env fallback)

let locate env position =
  let fallback = Option.value position.Position.filename ~default:"<unknown>" in
  Runtime.set_location position (fun () -> filename env fallback)

let bytes_of_value env value =
  let size = size_of_value env value in
  let at = Value.get_method value "at" 1 env in
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
