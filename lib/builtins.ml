let make_boolean env bool =
  let value = Value.uninitialized () in
  Value.add_method value "then-else" 2 (fun _ values ->
    match values with
    | [a; b] -> if bool then a else b
    | _ -> invalid_arg "wrong arity");
  Value.initialize value;
  let core   = Value.get_method env  "core"   0 env [] in
  let extend = Value.get_method core "extend" 0 env [] in
  Value.get_method extend "boolean" 1 env [value]

let number_comp env number op _ values =
  op number (List.hd values |> Value.as_number) |> make_boolean env

let string_of_number number =
  let neg = number < 0. in
  let number = Float.abs number in
  let s =
    if Float.is_integer number then
      string_of_int (truncate number)
    else string_of_float number
  in
  if neg then s ^ "-" else s

let int_of_value value =
  let n = Value.as_number value in
  if not (Float.is_integer n) then
    raise (Runtime.Error (
      "attempt to index using non-integer: " ^ string_of_number n,
      Position.zero));
  truncate n

let rec make_number env number =
  let value = Value.uninitialized () in
  Value.set_number value number;
  Value.add_method value "+"     1 (number_binop env number (+.));
  Value.add_method value "-"     1 (number_binop env number (-.));
  Value.add_method value "*"     1 (number_binop env number ( *. ));
  Value.add_method value "/"     1 (number_binop env number (/.));
  Value.add_method value "mod"   1
    (number_binop env number (fun a b -> mod_float (mod_float a b +. b) b));
  Value.add_method value "rem"   1 (number_binop env number mod_float);
  Value.add_method value "^"     1 (number_binop env number Float.pow);
  Value.add_method value "="     1 (number_comp  env number (=));
  Value.add_method value "<>"    1 (number_comp  env number (<>));
  Value.add_method value "<"     1 (number_comp  env number (<));
  Value.add_method value ">"     1 (number_comp  env number (>));
  Value.add_method value "<="    1 (number_comp  env number (<=));
  Value.add_method value ">="    1 (number_comp  env number (>=));
  Value.add_method value "floor" 0 (number_unop  env number Float.floor);
  Value.add_method value "ceil"  0 (number_unop  env number Float.ceil);
  Value.add_method value "trunc" 0 (number_unop  env number Float.trunc);
  Value.add_method value "to-string" 0
    (fun _ _ -> make_string env (string_of_number number));
  Value.initialize value;
  let core   = Value.get_method env  "core"   0 env [] in
  let extend = Value.get_method core "extend" 0 env [] in
  Value.get_method extend "number" 1 env [value]

and number_binop env number op _ values =
  op number (List.hd values |> Value.as_number) |> make_number env

and number_unop env number op _ _ = make_number env (op number)

and make_string env string =
  let value = Value.uninitialized () in
  let rec loop i () : _ Seq.node =
    if i < String.length string then
      let d = String.get_utf_8_uchar string i in
      let n =
        Uchar.utf_decode_uchar d |> Uchar.to_int |> float |> make_number env
      in
      Cons (n, loop (i + Uchar.utf_decode_length d))
    else Nil
  in
  let array = Array.of_seq (loop 0) in
  Value.add_method value "at" 1 (fun _ values ->
    let n = List.hd values |> int_of_value in
    if n < 0 || n >= Array.length array then
      raise (Runtime.Error
        ("index out of bounds: " ^ string_of_number (float n), Position.zero));
    array.(n));
  let size = make_number env (Array.length array |> float) in
  Value.add_method value "size" 0 (fun _ _ -> size);
  Value.initialize value;
  let core   = Value.get_method env  "core"   0 env [] in
  let extend = Value.get_method core "extend" 0 env [] in
  Value.get_method extend "string" 1 env [value]
