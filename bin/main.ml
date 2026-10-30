open Troopl

let report category message position =
  prerr_endline
    (Position.describe position ^ ": " ^ category ^ ": " ^ message);
  exit 1

let () =
  let program = Sys.argv.(0) in
  let experimental = Array.length Sys.argv > 1
    && Sys.argv.(1) = "--experimental" in
  let first = if experimental then 2 else 1 in
  if Array.length Sys.argv <= first then (
    prerr_endline ("usage: " ^ program ^ " <filename>");
    exit 1);
  let filename = Sys.argv.(first) in
  try
    let source = In_channel.with_open_bin filename In_channel.input_all in
    let lowered =
      Lexer.create ~filename source |> Parser.parse |> Lowerer.lower
    in
    let arguments = Array.sub Sys.argv first
      (Array.length Sys.argv - first) |> Array.to_list in
    let env = Env.make ~filename ~arguments () in
    let env = if experimental then Experimental.extend env else env in
    Evaluator.eval lowered.scope_size env lowered.ir
    |> ignore
  with
  | Lexer.Error   (message, pos) -> report "LEXER ERROR" message pos
  | Parser.Error  (message, pos) -> report "PARSER ERROR" message pos
  | Lowerer.Error (message, pos) -> report "LOWERING ERROR" message pos
  | Runtime.Error (message, pos) -> report "RUNTIME ERROR" message pos
  | Sys_error message ->
      prerr_endline (filename ^ ": IO ERROR: " ^ message);
      exit 1
