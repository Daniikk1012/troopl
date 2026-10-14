open Troopl

let read_file filename =
  In_channel.with_open_bin filename In_channel.input_all

let string_of_value value =
  let env = (Env.make ()) in
  let size =
    Value.get_method value "size" 0 env [] |> Builtins.int_of_value
  in
  let buffer = Buffer.create size in
  for i = 0 to size - 1 do
    let index = Builtins.make_number env (float i) in
    let code =
      Value.get_method value "at" 1 env [index] |> Builtins.int_of_value
    in
    Buffer.add_utf_8_uchar buffer (Uchar.of_int code)
  done;
  Buffer.contents buffer

let decode_output text =
  let buffer = Buffer.create (String.length text) in
  let rec loop i =
    if i < String.length text then
      if text.[i] = '\\' && i + 1 < String.length text then (
        let c = match text.[i + 1] with
          | 'n' -> '\n' | 'r' -> '\r' | 't' -> '\t' | '\\' -> '\\'
          | _ -> failwith "unknown stdout escape"
        in
        Buffer.add_char buffer c;
        loop (i + 2))
      else (Buffer.add_char buffer text.[i]; loop (i + 1))
  in
  loop 0;
  Buffer.contents buffer

let capture_output f =
  let filename = Filename.temp_file "troopl-example-" ".out" in
  let channel = open_out_bin filename in
  let saved = Unix.dup Unix.stdout in
  Fun.protect
    ~finally:(fun () ->
      flush stdout;
      Unix.dup2 saved Unix.stdout;
      Unix.close saved;
      close_out_noerr channel;
      Sys.remove filename)
    (fun () ->
      flush stdout;
      Unix.dup2 (Unix.descr_of_out_channel channel) Unix.stdout;
      let result = f () in
      flush stdout;
      result, read_file filename)

let check filename kind expected stdout_expected =
  let result, output = capture_output (fun () ->
    let lowered =
      read_file ("../examples/" ^ filename)
      |> Lexer.create |> Parser.parse |> Lowerer.lower
    in
    Evaluator.eval lowered.scope_size (Env.make ()) lowered.ir)
  in
  let actual = match kind with
    | "number" -> Value.as_number result |> Builtins.string_of_number
    | "string" -> string_of_value result
    | _ -> failwith ("unknown expectation kind: " ^ kind)
  in
  if actual <> expected then
    failwith (filename ^ ": expected " ^ expected ^ ", got " ^ actual);
  if output <> decode_output stdout_expected then
    failwith (Printf.sprintf "%s: unexpected stdout %S" filename output)

let () =
  let rows =
    read_file "../examples/expectations.tsv" |> String.split_on_char '\n'
    |> List.filter (fun row -> row <> "" && row.[0] <> '#')
  in
  if List.length rows <> 50 then failwith "expected exactly 50 examples";
  let names = List.map (fun row ->
    match String.split_on_char '\t' row with
    | [filename; kind; expected; output] ->
        (try check filename kind expected output with
         | exn -> failwith (filename ^ ": " ^ Printexc.to_string exn));
        filename
    | _ -> failwith ("invalid expectation row: " ^ row)) rows
  in
  let actual_files =
    Sys.readdir "../examples" |> Array.to_list
    |> List.filter (fun name -> Filename.check_suffix name ".tr")
    |> List.sort String.compare
  in
  if actual_files <> List.sort_uniq String.compare names then
    failwith "example files and expectation manifest differ";
  print_endline "50 examples passed (returned values and stdout)"
