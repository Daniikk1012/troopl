open Troopl

let lower string scope_size =
  let lowered = Lexer.create string |> Parser.parse |> Lowerer.lower in
  assert (lowered.scope_size = scope_size);
  lowered.ir

let () = match lower "" 0 with Environment -> () | _ -> assert false

let () =
  match lower "A 1 B A B" 2 with
  | Definition {
      index = 0;
      value = Number 1.;
      scope = Definition { index = 1; value = Variable 0; scope = Variable 1};
    } -> ()
  | _ -> assert false

let () =
  match lower "A 1 B {a (A) b X (B) c C (C)} C 2 C" 3 with
  | Definition {
      index = 0;
      value = Number 1.;
      scope = RecursiveDefinition {
        index = 1;
        entries = [
          Method {
            name       = "a";
            args       = [];
            body       = Variable 0;
            captures   = [{ outer = 0; inner = 0 }];
            scope_size = 1;
          };
          Method {
            name       = "b";
            args       = [None];
            body       = Variable 0;
            captures   = [{ outer = 1; inner = 0 }];
            scope_size = 1;
          };
          Method {
            name       = "c";
            args       = [Some 0];
            body       = Variable 0;
            captures   = [];
            scope_size = 1;
          };
        ];
        scope = Definition { index = 2; value = Number 2.; scope = Variable 2 };
      };
    } -> ()
  | _ -> assert false

let () =
  match lower "1 2 3" 0 with
  | Sequence (Number 1., Sequence (Number 2., Number 3.)) -> ()
  | _ -> assert false

let () =
  match
    lower "A 1 B 2 {A B a A B ((A) B) b C D ((B) A) c A ((A) B) d B ((A) B)}" 2
  with
  | Definition {
      index = 0;
      value = Number 1.;
      scope = Definition {
        index = 1;
        value = Number 2.;
        scope = Object [
          Inclusion { value = Variable 0 };
          Inclusion { value = Variable 1 };
          Method {
            name       = "a";
            args       = [Some 0; Some 1];
            body       = Sequence (Variable 0, Variable 1);
            captures   = [];
            scope_size = 2;
          };
          Method {
            name       = "b";
            args       = [None; None];
            body       = Sequence (Variable 0, Variable 1);
            captures   = [{ outer = 0; inner = 1 }; { outer = 1; inner = 0 }];
            scope_size = 2;
          };
          Method {
            name       = "c";
            args       = [Some 0];
            body       = Sequence (Variable 0, Variable 1);
            captures   = [{ outer = 1; inner = 1 }];
            scope_size = 2;
          };
          Method {
            name       = "d";
            args       = [Some 1];
            body       = Sequence (Variable 0, Variable 1);
            captures   = [{ outer = 0; inner = 0 }];
            scope_size = 2;
          };
        ];
      };
    } -> ()
  | _ -> assert false

let () =
  match lower "A (A 1) A A" 3 with
  | Definition {
      index = 1;
      value = Definition { index = 0; value = Number 1.; scope = Variable 0 };
      scope = Definition { index = 2; value = Variable 1; scope = Variable 2 };
    } -> ()
  | _ -> assert false

let () =
  match lower "\"abc\"" 0 with
  | String "abc" -> ()
  | _ -> assert false

let () =
  match lower "1 + 2 - 3" 0 with
  | Call {
      value = Call { value = Number 1.; name = "+"; args = [Number 2.] };
      name = "-";
      args = [Number 3.];
    } -> ()
  | _ -> assert false

let () =
  try ignore (lower "{a A A (A)}" 0); assert false with Lowerer.Error _ -> ()

let () = try ignore (lower "A" 0); assert false with Lowerer.Error _ -> ()

let () = print_endline "test_lowerer successful"
