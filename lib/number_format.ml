let expand_decimal text =
  match String.index_opt text 'e' with
  | None -> text
  | Some i ->
      let mantissa = String.sub text 0 i in
      let exponent =
        String.sub text (i + 1) (String.length text - i - 1) |> int_of_string
      in
      let point =
        Option.value
          (String.index_opt mantissa '.')
          ~default:(String.length mantissa)
      in
      let digits = String.concat "" (String.split_on_char '.' mantissa) in
      let point = point + exponent in
      if point <= 0 then "0." ^ String.make (-point) '0' ^ digits
      else if point >= String.length digits then
        digits ^ String.make (point - String.length digits) '0'
      else
        String.sub digits 0 point ^ "."
        ^ String.sub digits point (String.length digits - point)

(* The fewest significant digits (at most 17) that read back as the same
   float, so 0.1 prints as 0.1 rather than 0.10000000000000001. *)
let shortest number =
  let rec loop precision =
    let text = Printf.sprintf "%.*g" precision number in
    if precision >= 17 || float_of_string text = number then text
    else loop (precision + 1)
  in
  loop 15

let string_of_number number =
  if Float.is_nan number then "0nan"
  else if number = infinity then "0inf"
  else if number = neg_infinity then "0inf-"
  else
    let text = shortest (Float.abs number) |> expand_decimal in
    let text =
      if String.ends_with ~suffix:"." text then
        String.sub text 0 (String.length text - 1)
      else text
    in
    if Float.sign_bit number then text ^ "-" else text

let int_of_number n =
  if (not (Float.is_integer n)) || n < float min_int || n >= float max_int then
    Runtime.error ("expected a finite integer: " ^ string_of_number n);
  int_of_float n
