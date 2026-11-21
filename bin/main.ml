open Troopl

let usage =
  "usage: troopl [--tokens | --ast | --ir] <file> [arguments...]\n\
  \       troopl --help | --version"

let help =
  usage
  ^ "\n\n\
     Runs a TrOOPL program. The file name and the arguments after it are\n\
     available to the program through system args.\n\n\
     options:\n\
    \  --tokens   print the tokens of <file> and exit\n\
    \  --ast      print the parsed expression tree of <file> and exit\n\
    \  --ir       print the lowered intermediate representation and exit\n\
    \  --help     print this help and exit\n\
    \  --version  print the version and exit\n\
    \  --         end of options; the next argument is the file"

let version = "troopl, implementing the TrOOPL specification v0.2"

type mode = Run | Tokens | Ast | Ir

let report category message position =
  prerr_endline (Position.describe position ^ ": " ^ category ^ ": " ^ message);
  exit 1

let print_tokens lexer =
  let rec loop () =
    let token = Lexer.next_token lexer in
    print_endline (Token.to_string token);
    if token.kind <> Eof then loop ()
  in
  loop ()

let run mode filename arguments =
  try
    let source = In_channel.with_open_bin filename In_channel.input_all in
    let lexer = Lexer.create ~filename source in
    match mode with
    | Tokens -> print_tokens lexer
    | Ast -> print_endline (Expression.to_string (Parser.parse lexer))
    | Ir ->
        print_endline (Ir.to_string (Parser.parse lexer |> Lowerer.lower).ir)
    | Run ->
        let lowered = Parser.parse lexer |> Lowerer.lower in
        let env = Env.make ~filename ~arguments:(filename :: arguments) () in
        Evaluator.eval lowered.scope_size env lowered.ir |> ignore
  with
  | Lexer.Error (message, pos) -> report "LEXER ERROR" message pos
  | Parser.Error (message, pos) -> report "PARSER ERROR" message pos
  | Lowerer.Error (message, pos) -> report "LOWERING ERROR" message pos
  | Runtime.Error (message, pos) -> report "RUNTIME ERROR" message pos
  | Sys_error message ->
      prerr_endline (filename ^ ": IO ERROR: " ^ message);
      exit 1
  | Stack_overflow ->
      (* The evaluator reports guest recursion with a position; this covers
         the recursive-descent parser on deeply nested brackets. *)
      prerr_endline (filename ^ ": STACK OVERFLOW: nesting is too deep");
      exit 1

let () =
  let fail message =
    prerr_endline message;
    exit 1
  in
  match List.tl (Array.to_list Sys.argv) with
  | [ "--help" ] | [ "-h" ] -> print_endline help
  | [ "--version" ] -> print_endline version
  | mode :: rest when String.length mode > 1 && mode.[0] = '-' && mode <> "--"
    -> (
      let mode =
        match mode with
        | "--tokens" -> Tokens
        | "--ast" -> Ast
        | "--ir" -> Ir
        | _ -> fail ("unknown option " ^ mode ^ "\n" ^ usage)
      in
      match rest with
      | [ "--"; filename ] | [ filename ] -> run mode filename []
      | _ -> fail usage)
  | "--" :: filename :: arguments | filename :: arguments ->
      run Run filename arguments
  | [] -> fail usage
