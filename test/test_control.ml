open Troopl
let env = Experimental.extend (Env.make ())
let eval source =
  let ir = Lexer.create ~filename:"control.tr" source
    |> Parser.parse |> Lowerer.lower in
  Evaluator.eval ir.scope_size env ir.ir
let number source n = assert (Value.as_number (eval source) = n)
let () =
  number "control escape {run Exit (Exit return 7)}" 7.;
  number "control escape {run Exit 8}" 8.;
  number "control escape {run Outer (control escape {run Inner (Outer return 9)})}" 9.;
  number "B (box 0) R (control escape {run Exit (control ensure [Exit return 7] [B set 9])}) R + (B get)" 16.;
  number "B (box 0) R (control ensure [7] [B set 9]) R + (B get)" 16.;
  number "B (box 0) (control ensure [control ensure [7] [B set 1]] [B set ((B get) + 2)]) B get" 3.;
  let failed = try ignore (eval
    "B (box {}) (control escape {run Exit ((B set Exit) 7)}) B get return 9");
    false with Runtime.Error _ -> true in
  assert failed;
  let message = try
    ignore (eval "control ensure [(crash \"body\")] [(crash \"cleanup\") ]");
    "" with Runtime.Error (message,_) -> message in
  assert (message = "body");
  let message = try
    ignore (eval "control ensure [7] [(crash \"cleanup\")]");
    "" with Runtime.Error (message,_) -> message in
  assert (message = "cleanup");
  let message = try
    ignore (eval "control escape {run Exit (crash \"fatal\")}");
    "" with Runtime.Error (message,_) -> message in
  assert (message = "fatal");
  number "control escape {run Exit (L {run I (I < 1000000 then-else [L run (I + 1)] [Exit return I] run)} L run 0)}" 1000000.;
  let body = Value.uninitialized () in
  Value.add_method body "run" 1 (fun env args ->
    let exit = List.hd args in
    let outcome = Domain.spawn (fun () ->
      try ignore (Value.get_method exit "return" 1 env [Value.empty ()]); false
      with Runtime.Error _ -> true) |> Domain.join in
    assert outcome;
    Value.empty ());
  Value.initialize body;
  ignore (Control.escape env body);
  print_endline "12 scoped-control checks passed"
