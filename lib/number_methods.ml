(** Pure numeric operations. The single sorted table is initialized before
    any guest execution and never exposed for mutation. *)
type operation =
  | Unary of (float -> float)
  | Binary of (float -> float -> float)
  | Comparison of (float -> float -> bool)
  | To_string

let methods =
  let unary name op = Selector.intern name 0, Unary op in
  let binary name op = Selector.intern name 1, Binary op in
  let comparison name op = Selector.intern name 1, Comparison op in
  let methods = [|
    binary "+" ( +. ); binary "-" ( -. ); binary "*" ( *. );
    binary "/" ( /. ); binary "rem" mod_float; binary "^" Float.pow;
    binary "mod" (fun a b ->
      let divisor = Float.abs b in
      let remainder = mod_float a divisor in
      if remainder < 0. then remainder +. divisor else remainder);
    comparison "=" ( = ); comparison "<>" ( <> );
    comparison "<" ( < ); comparison ">" ( > );
    comparison "<=" ( <= ); comparison ">=" ( >= );
    unary "-" (fun n -> -. n); unary "floor" Float.floor;
    unary "ceil" Float.ceil; unary "trunc" Float.trunc;
    Native_selectors.id_to_string_0, To_string
  |] in
  Array.sort (fun (a, _) (b, _) -> compare a b) methods;
  methods

let index selector =
  let rec search low high =
    if low > high then -1 else
    let i = (low + high) / 2 in
    let key, _ = methods.(i) in
    if key = selector then i
    else if key < selector then (search [@tailcall]) (i + 1) high
    else (search [@tailcall]) low (i - 1)
  in
  search 0 (Array.length methods - 1)

let mem selector = index selector >= 0
let find selector =
  let i = index selector in
  if i < 0 then raise Not_found;
  snd methods.(i)
let iter_selectors f = Array.iter (fun (selector, _) -> f selector) methods

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

let int_of_number n =
  if not (Float.is_integer n)
     || n < float min_int || n >= float max_int then
    Runtime.error ("expected a finite integer: " ^ string_of_number n);
  int_of_float n

