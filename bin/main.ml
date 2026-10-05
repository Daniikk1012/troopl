open Troopl

let () =
  let program =
    if Array.length Sys.argv >= 1 then Sys.argv.(0) else "<program>"
  in
  if Array.length Sys.argv <> 2 then (
    prerr_endline ("usage: " ^ program ^ " <filename>");
    exit 1);
  let filename = Sys.argv.(1) in
  let string = In_channel.with_open_text filename In_channel.input_all in
  try
    let lowered = Lexer.create string |> Parser.parse |> Lowerer.lower in
    Evaluator.eval lowered.scope_size Env.default lowered.ir |> ignore
  with
  | Lexer.Error (message, pos) ->
      prerr_endline (Position.to_string pos ^ ": " ^ "LEXER ERROR: " ^ message)
  | Parser.Error (message, pos) ->
      prerr_endline (Position.to_string pos ^ ": " ^ "PARSER ERROR: " ^ message)
  | Lowerer.Error (message, pos) -> prerr_endline
      (Position.to_string pos ^ ": " ^ "LOWERING ERROR: " ^ message)
  | Runtime.Error (message, pos) -> prerr_endline
      (Position.to_string pos ^ ": " ^ "RUNTIME ERROR: " ^ message)
