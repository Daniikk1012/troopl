open Troopl

let checks = ref 0

let check name ok =
  incr checks;
  if not ok then failwith name

let base = Env.make ()

let call env object_ name args =
  Value.get_method object_ name (List.length args) env args

let occurrences text needle =
  let count = ref 0 in
  for i = 0 to String.length text - String.length needle do
    if String.sub text i (String.length needle) = needle then incr count
  done;
  !count

let () =
  let events = ref [] in
  let extension = Value.uninitialized () in
  List.iter
    (fun name ->
      Value.add_method extension name 1 (fun _ args ->
          let value = List.hd args in
          events :=
            (name, if name = "number" then Value.as_number value else 0.)
            :: !events;
          value))
    [ "number"; "boolean"; "string"; "list" ];
  Value.initialize extension;
  let core = Value.uninitialized () in
  Value.add_method core "extend" 0 (fun _ _ -> extension);
  Value.initialize core;
  let env = Value.uninitialized () in
  Value.add_methods env base;
  Value.add_method env "core" 0 (fun _ _ -> core);
  Value.initialize env;
  let a = Builtins.make_number env 12. and b = Builtins.make_number env 3. in
  events := [];
  check "arithmetic value" (Value.as_number (call env a "+" [ b ]) = 15.);
  check "arithmetic hook once" (!events = [ ("number", 15.) ]);
  events := [];
  ignore (call env a "<" [ b ]);
  check "comparison uses boolean hook" (!events = [ ("boolean", 0.) ]);
  events := [];
  ignore (call env a "to-string" []);
  check "to-string hook order"
    (List.rev !events
    = [ ("number", 49.); ("number", 50.); ("number", 2.); ("string", 0.) ]);
  events := [];
  ignore (Builtins.make_byte_string env "\255A");
  check "lossless string hook order"
    (List.rev !events
    = [ ("number", -255.); ("number", 65.); ("number", 2.); ("string", 0.) ]);
  let bound = Value.bind env a in
  events := [];
  ignore (call base bound "-" []);
  check "bound numeric result uses bound environment"
    (!events = [ ("number", -12.) ]);
  let extracted = Value.get_method a "+" 1 in
  check "extracted numeric closure retains original payload"
    (Value.as_number (extracted base [ b ]) = 15.);
  let callbacks = ref 0 in
  let source = Value.uninitialized () in
  Value.add_method source "duplicate" 0 (fun _ _ -> a);
  Value.initialize source;
  let wrapped = Value.bind ~before:(fun () -> incr callbacks) env source in
  let current = ref wrapped in
  for _ = 1 to 24 do
    let next = Value.uninitialized () in
    Value.add_methods next !current;
    Value.add_methods next wrapped;
    Value.add_method next "other" 0 (fun _ _ -> b);
    current := Value.finish next
  done;
  check "enumeration and flattening do not invoke callbacks" (!callbacks = 0);
  let description = Value.to_string !current in
  check "description deduplicates shadowed selectors"
    (occurrences description "duplicate/0" = 1
    && occurrences description "other/0" = 1);
  check "description does not invoke callbacks" (!callbacks = 0);
  check "flattened winner" (call base !current "duplicate" [] == a);
  check "flattened callable runs callback once" (!callbacks = 1);
  check "flattened object stays bounded" (Value.storage_depth !current <= 8);
  let bad_env = Value.empty () in
  check "missing core is not bypassed"
    (try
       ignore (Builtins.make_number bad_env 1.);
       false
     with Runtime.Error _ -> true);
  Printf.printf "%d layout-review checks passed\n" !checks
