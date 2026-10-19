let () =
  if Array.length Sys.argv = 1 then print_endline "child-ready" else
  match Sys.argv.(1) with
  | "echo" ->
      let input = In_channel.input_all stdin in
      output_string stdout ("out:" ^ input ^ "\255");
      output_string stderr "error\254"
  | "args" ->
      for i = 2 to Array.length Sys.argv - 1 do
        output_string stdout Sys.argv.(i);
        output_char stdout '\n'
      done
  | "empty" ->
      if In_channel.input_all stdin <> "" then exit 9
  | "flood" ->
      output_string stdout (String.make 70000 'a');
      output_string stderr (String.make 70000 'b');
      flush stdout;
      flush stderr;
      In_channel.input_all stdin |> String.length |> Printf.printf "%d"
  | "exit" -> exit 7
  | _ -> exit 2
