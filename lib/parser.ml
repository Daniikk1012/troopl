type t = { lexer : Lexer.t; mutable token : Token.t }

exception Error of string * Position.t

let advance parser = parser.token <- Lexer.next_token parser.lexer

let expected message parser =
  raise (Error (
    "unexpected token " ^ Token.string_of_kind parser.token.kind ^ ", expected "
      ^ message,
    parser.token.pos))

let expect kind parser =
  if parser.token.kind = kind then
    advance parser
  else expected (Token.string_of_kind kind) parser

let is_value_start (kind : Token.kind) =
  match kind with
  | Variable _ | Number _ | String _ | OpenParen | OpenObject | OpenBlock ->
      true
  | _ -> false

let rec parse_statements parser : Expression.t =
  match parser.token with
  | { kind = Variable name; pos } -> (
      let variable = parse_value parser in
      match parser.token.kind with
      | Variable _ | Number _ | String _ | OpenParen -> (
          let value = parse_value parser in
          match parser.token.kind with
          | kind when is_value_start kind ->
              let scope = parse_statements parser in
              { kind = Definition { name; value; scope }; pos }
          | _ -> { kind = Definition { name; value; scope = variable }; pos })
      | OpenBlock | OpenObject -> (
          let entries = parse_object_like parser in
          match parser.token.kind with
          | kind when is_value_start kind ->
              let scope = parse_statements parser in
              { kind = RecursiveDefinition { name; entries; scope }; pos }
          | _ ->
              let scope = variable in
              { kind = RecursiveDefinition { name; entries; scope }; pos })
      | Method _ -> parse_call variable parser
      | _ -> variable)
  | { kind; pos } when is_value_start kind -> (
      let expr = parse_value parser in
      match parser.token.kind with
      | kind when is_value_start kind ->
          { kind = Sequence (expr, parse_statements parser); pos }
      | Method _ -> parse_call expr parser
      | _ -> expr)
  | { kind = Method _; pos } -> parse_call { kind = Environment; pos } parser
  | { pos } -> { kind = Environment; pos }

and parse_value parser =
  match parser.token with
  | { kind = Variable v; pos } -> advance parser; { kind = Variable v; pos }
  | { kind = Number   n; pos } -> advance parser; { kind = Number   n; pos }
  | { kind = String   s; pos } -> advance parser; { kind = String   s; pos }
  | { kind = OpenParen } ->
      advance parser;
      let expr = parse_statements parser in
      expect CloseParen parser;
      expr
  | { kind = OpenObject | OpenBlock } ->
      let pos = parser.token.pos in
      let entries = parse_object_like parser in
      { kind = Object entries; pos }
  | _ -> expected
      "Variable, Number, String, OpenParen, OpenObject, or OpenBlock" parser

and parse_object_like parser =
  match parser.token with
  | { kind = OpenObject } ->
      advance parser;
      let entries = parse_entries parser in
      expect CloseObject parser;
      entries
  | { kind = OpenBlock; pos } ->
      advance parser;
      let body = parse_statements parser in
      expect CloseBlock parser;
      [{ kind = Method { name = "run"; args = []; body }; pos }]
  | _ -> expected "OpenObject or OpenBlock" parser

and parse_entries parser =
  match parser.token with
  | { kind = Method name; pos } -> 
      advance parser;
      let args = parse_args parser in
      let body = parse_value parser in
      let entry : Expression.entry =
        { kind = Method { name; args; body }; pos }
      in
      entry :: parse_entries parser
  | { kind; pos } when is_value_start kind ->
      let entry : Expression.entry =
        { kind = Inclusion (parse_value parser); pos }
      in
      entry :: parse_entries parser
  | _ -> []

and parse_args parser =
  match parser.token.kind with
  | Variable name -> advance parser; name :: parse_args parser
  | _ -> []

and parse_call value parser =
  match parser.token with
  | { kind = Method name; pos } ->
      advance parser;
      let args = parse_values parser in
      parse_call { kind = Call { value; name; args }; pos } parser
  | _ -> value

and parse_values parser =
  if is_value_start parser.token.kind then
    let value = parse_value parser in value :: parse_values parser
  else []

let parse_program parser =
  let expr = parse_statements parser in
  expect Eof parser;
  expr

let parse lexer = parse_program { lexer; token = Lexer.next_token lexer }
