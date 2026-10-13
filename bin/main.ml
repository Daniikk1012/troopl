open Troopl

let report category message position =
  prerr_endline
    (Position.describe position ^ ": " ^ category ^ ": " ^ message);
  exit 1

let () =
  let program = Sys.argv.(0) in
  if Array.length Sys.argv <> 2 then (
    prerr_endline ("usage: " ^ program ^ " <filename>");
    exit 1);
  let filename = Sys.argv.(1) in
  let start = Position.with_filename filename Position.zero in
  try
    let source = In_channel.with_open_bin filename In_channel.input_all in
    let lowered =
      Lexer.create ~filename source |> Parser.parse |> Lowerer.lower
    in
    Evaluator.eval lowered.scope_size (Env.make ~filename ()) lowered.ir
    |> ignore
  with
  | Lexer.Error (message, pos) -> report "LEXER ERROR" message pos
  | Parser.Error (message, pos) -> report "PARSER ERROR" message pos
  | Lowerer.Error (message, pos) -> report "LOWERING ERROR" message pos
  | Runtime.Error (message, pos) -> report "RUNTIME ERROR" message pos
  | Sys_error message -> report "IO ERROR" message start
