let finish = Value.finish
let extend = Value.extend
let make_boolean = Value.make_boolean
let make_number = Value.make_number
let make_string = Value.make_string
let make_byte_string = Value.make_byte_string
let int_of_value = Value.int_of_value
let string_of_number = Number_methods.string_of_number

let size_of_value env value =
  let result = Runtime.resume (fun () ->
    Value.get_method_id value Native_selectors.id_size_0 env []) in
  let size = int_of_value result in
  if size < 0 then Runtime.error ("invalid size " ^ string_of_int size);
  size

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

let make_list env values =
  extend env Native_selectors.id_list_1 (minimal_list env values)

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
