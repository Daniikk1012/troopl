type t = { input : string; mutable pos : Position.t }

exception Error of string * Position.t

let create input = { input; pos = Position.zero }

let get_utf_8_uchar lexer =
  let d = String.get_utf_8_uchar lexer.input lexer.pos.offset in
  if Uchar.utf_decode_is_valid d then
    Uchar.utf_decode_uchar d
  else raise (Error ("invalid UTF-8", lexer.pos))

let get_char lexer =
  if lexer.pos.offset < String.length lexer.input then
    Some (String.get lexer.input lexer.pos.offset)
  else None

let advance lexer = lexer.pos <- Position.next (get_utf_8_uchar lexer) lexer.pos

let length_while f lexer =
  let rec loop n =
    match get_char lexer with
    | Some c when f c -> advance lexer; loop (n + 1)
    | _ -> n
  in
  loop 0

let take_while f lexer =
  let len = length_while f lexer in
  String.sub lexer.input (lexer.pos.offset - len) len

let is_ident_part = function
  | ' ' | '#' | '\t' | '\r' | '\n' | '(' | ')' | '[' | ']' | '{' | '}' | '"' ->
      false
  | _ -> true

let take_ident lexer = take_while is_ident_part lexer

let is_number_part = function '0' .. '9' | '.' -> true | _ -> false

let number_of_string s =
  let (s, k) =
    if String.ends_with ~suffix:"-" s then
      (String.sub s 0 (String.length s - 1), -1.)
    else (s, 1.)
  in
  if (String.for_all is_number_part s) then
    float_of_string_opt s |> Option.map (fun x -> x *. k)
  else None

let take_string lexer =
  let buf = Buffer.create 16 in
  let rec loop () =
    match get_char lexer with
    | Some '"' -> (
        advance lexer;
        match get_char lexer with
        | Some '"' -> advance lexer; Buffer.add_char buf '"'; loop ()
        | _ -> Buffer.contents buf)
    | Some '\r' -> advance lexer; loop ()
    | Some c -> advance lexer; Buffer.add_char buf c; loop ()
    | None -> raise (Error ("unexpected EOF, expected '\"'", lexer.pos))
  in
  loop ()

let rec next_token lexer : Token.t =
  match get_char lexer with
  | Some (' ' | '\t' | '\r' | '\n') -> advance lexer; next_token lexer
  | Some '#' ->
      ignore (length_while (fun x -> x <> '\n') lexer); next_token lexer
  | c ->
      let pos = lexer.pos in
      let kind : Token.kind = match c with
        | Some '(' -> advance lexer; OpenParen
        | Some ')' -> advance lexer; CloseParen
        | Some '{' -> advance lexer; OpenObject
        | Some '}' -> advance lexer; CloseObject
        | Some '[' -> advance lexer; OpenBlock
        | Some ']' -> advance lexer; CloseBlock
        | Some '0'..'9' -> (
            let s = take_ident lexer in
            match number_of_string s with
            | Some x -> Number x
            | None ->
                raise (Error ("invalid numeric literal \"" ^ s ^ "\"", pos)))
        | Some '"' -> advance lexer; Token.String (take_string lexer)
        | Some _
          when let cat = get_utf_8_uchar lexer |> Uucp.Gc.general_category in
               cat = `Lu || cat = `Lt ->
            Variable (take_ident lexer)
        | Some _ -> Method (take_ident lexer)
        | None -> Eof
      in
      { kind; pos }
