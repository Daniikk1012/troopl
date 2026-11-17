open Troopl

let parse string = Lexer.create string |> Parser.parse
let () = match parse "" with { kind = Environment } -> () | _ -> assert false

let () =
  match parse "1 + 2" with
  | {
   kind =
     Call
       {
         value =
           { kind = Number 1.; pos = { offset = 0; line = 1; column = 1 } };
         name = "+";
         args =
           [ { kind = Number 2.; pos = { offset = 4; line = 1; column = 5 } } ];
       };
   pos = { offset = 2; line = 1; column = 3 };
  } ->
      ()
  | _ -> assert false

let () =
  match parse "A B C 1 D \"d\" E () F" with
  | {
   kind =
     Definition
       {
         name = "A";
         value = { kind = Variable "B" };
         scope =
           {
             kind =
               Definition
                 {
                   name = "C";
                   value = { kind = Number 1. };
                   scope =
                     {
                       kind =
                         Definition
                           {
                             name = "D";
                             value = { kind = String "d" };
                             scope =
                               {
                                 kind =
                                   Definition
                                     {
                                       name = "E";
                                       value = { kind = Environment };
                                       scope = { kind = Variable "F" };
                                     };
                               };
                           };
                     };
                 };
           };
       };
  } ->
      ()
  | _ -> assert false

let () =
  match parse "A [] B {c ()} D" with
  | {
   kind =
     RecursiveDefinition
       {
         name = "A";
         entries =
           [
             {
               kind =
                 Method
                   { name = "run"; args = []; body = { kind = Environment } };
             };
           ];
         scope =
           {
             kind =
               RecursiveDefinition
                 {
                   name = "B";
                   entries =
                     [
                       {
                         kind =
                           Method
                             {
                               name = "c";
                               args = [];
                               body = { kind = Environment };
                             };
                       };
                     ];
                   scope = { kind = Variable "D" };
                 };
           };
       };
  } ->
      ()
  | _ -> assert false

let () =
  match parse "(A) 1. B" with
  | {
   kind =
     Sequence
       ( { kind = Variable "A" },
         { kind = Sequence ({ kind = Number 1. }, { kind = Variable "B" }) } );
  } ->
      ()
  | _ -> assert false

let () =
  match parse "A 1" with
  | {
   kind =
     Definition
       {
         name = "A";
         value = { kind = Number 1. };
         scope = { kind = Variable "A" };
       };
  } ->
      ()
  | _ -> assert false

let () =
  match parse "{A 1 b C D (E) f (G) \"h\"}" with
  | {
   kind =
     Object
       [
         { kind = Inclusion { kind = Variable "A" } };
         { kind = Inclusion { kind = Number 1. } };
         {
           kind =
             Method
               {
                 name = "b";
                 args = [ "C"; "D" ];
                 body = { kind = Variable "E" };
               };
         };
         {
           kind =
             Method { name = "f"; args = []; body = { kind = Variable "G" } };
         };
         { kind = Inclusion { kind = String "h" } };
       ];
  } ->
      ()
  | _ -> assert false

let () =
  match parse "a b c" with
  | {
   kind =
     Call
       {
         value =
           {
             kind =
               Call
                 {
                   value =
                     {
                       kind =
                         Call
                           {
                             value = { kind = Environment };
                             name = "a";
                             args = [];
                           };
                     };
                   name = "b";
                   args = [];
                 };
           };
         name = "c";
         args = [];
       };
  } ->
      ()
  | _ -> assert false

let () =
  match parse "A B C d" with
  | {
   kind =
     Definition
       {
         name = "A";
         value = { kind = Variable "B" };
         scope =
           {
             kind =
               Call { value = { kind = Variable "C" }; name = "d"; args = [] };
           };
       };
  } ->
      ()
  | _ -> assert false

let () =
  match parse "A b c D e F G" with
  | {
   kind =
     Call
       {
         value =
           {
             kind =
               Call
                 {
                   value =
                     {
                       kind =
                         Call
                           {
                             value = { kind = Variable "A" };
                             name = "b";
                             args = [];
                           };
                     };
                   name = "c";
                   args = [ { kind = Variable "D" } ];
                 };
           };
         name = "e";
         args = [ { kind = Variable "F" }; { kind = Variable "G" } ];
       };
  } ->
      ()
  | _ -> assert false

let () =
  try
    ignore (parse "A B c");
    assert false
  with Parser.Error _ -> ()

let () =
  try
    ignore (parse "(");
    assert false
  with Parser.Error _ -> ()

let () =
  try
    ignore (parse "[");
    assert false
  with Parser.Error _ -> ()

let () =
  try
    ignore (parse "{");
    assert false
  with Parser.Error _ -> ()

let () =
  try
    ignore (parse "{a}");
    assert false
  with Parser.Error _ -> ()

let () =
  try
    ignore (parse "{a B}");
    assert false
  with Parser.Error _ -> ()

let () =
  try
    ignore (parse "{a b ()}");
    assert false
  with Parser.Error _ -> ()

let () = print_endline "test_parser successful"

let contains text needle =
  let n = String.length needle in
  let rec scan i =
    i + n <= String.length text && (String.sub text i n = needle || scan (i + 1))
  in
  scan 0

let parse_error source =
  try
    ignore (parse source);
    assert false
  with Parser.Error (message, pos) -> (message, pos)

let () =
  let message, _ = parse_error "(" in
  assert (message = "unexpected end of file, expected ')'");
  let message, pos = parse_error "X {get Y}" in
  assert (pos.offset = 8);
  assert (contains message "\"Y\" is a parameter of method \"get\"");
  assert (contains message "write \"(Y)\"");
  let message, _ = parse_error "X {get}" in
  assert (not (contains message "parameter"))
