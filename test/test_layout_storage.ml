open Troopl

let checks = ref 0
let check name condition = incr checks; if not condition then failwith name
let env = Env.make ()
let call object_ name = Value.get_method object_ name 0 env []
let object_with name result =
  let object_ = Value.uninitialized () in
  Value.add_method object_ name 0 (fun _ _ -> result);
  Value.finish object_
let include_ source =
  let object_ = Value.uninitialized () in
  Value.add_methods object_ source;
  object_
let fails f = try f (); false with Runtime.Error _ -> true

let () =
  let one = Builtins.make_number env 1. in
  let two = Builtins.make_number env 2. in
  let source = object_with "answer" one in
  let copy = include_ source in
  Value.add_method copy "answer" 0 (fun _ _ -> two);
  Value.add_method copy "extra" 0 (fun _ _ -> one);
  Value.initialize copy;
  check "included source remains immutable" (call source "answer" == one);
  check "local override wins" (call copy "answer" == two);
  let later = object_with "answer" one in
  let merged = include_ copy in
  Value.add_method merged "before" 0 (fun _ _ -> two);
  Value.add_methods merged later;
  Value.add_method merged "after" 0 (fun _ _ -> two);
  Value.initialize merged;
  check "later inclusion wins" (call merged "answer" == one);
  check "earlier delta survives inclusion" (call merged "before" == two);
  check "earlier base survives inclusion" (call merged "extra" == one);
  check "new delta survives inclusion" (call merged "after" == two);
  check "source delta not mutated" (call copy "answer" == two);
  let many = ref merged in
  for i = 1 to 200 do
    let next = include_ !many in
    Value.add_methods next (object_with "answer" (if i mod 2 = 0 then two else one));
    many := Value.finish next;
    check "bounded inclusion depth" (Value.storage_depth !many <= 8)
  done;
  check "deep inclusion winner" (call !many "answer" == two);
  check "deep inclusion preserves unrelated method" (call !many "before" == two);
  let weak = Weak.create 1 in
  let retained () =
    let payload = Bytes.make 8388608 'x' in
    Weak.set weak 0 (Some payload);
    let object_ = Value.uninitialized () in
    Value.add_method object_ "hidden" 0 (fun _ _ ->
      ignore (Sys.opaque_identity payload); one);
    Value.finish object_
  in
  let replaced = ref (retained ()) in
  for _ = 1 to 40 do
    let next = include_ !replaced in
    Value.add_method next "hidden" 0 (fun _ _ -> two);
    replaced := Value.finish next
  done;
  Gc.full_major ();
  check "flattening releases overwritten lexical payload" (not (Weak.check weak 0));
  check "flattened replacement callable works" (call !replaced "hidden" == two);
  let seen = ref [] in
  let dynamic = Value.uninitialized () in
  Value.add_method dynamic "environment" 0 (fun env _ -> env);
  Value.initialize dynamic;
  let first = Value.bind ~before:(fun () -> seen := 1 :: !seen) one dynamic in
  let second = Value.bind ~before:(fun () -> seen := 2 :: !seen) two first in
  check "nested bind keeps innermost environment" (call second "environment" == one);
  check "nested bind callback order" (!seen = [1; 2]);
  seen := [];
  check "missing lookup does not run callbacks"
    (fails (fun () -> ignore (call second "absent")) && !seen = []);
  let direct = Value.invoke_id second (Selector.intern "environment" 0) env [] in
  check "direct invocation keeps binding" (direct == one && !seen = [1; 2]);
  let tagged = include_ one in
  Value.set_number tagged 99.;
  Value.initialize tagged;
  let bound = Value.bind env tagged in
  check "binding preserves independent numeric tag" (Value.as_number bound = 99.);
  check "binding preserves original arithmetic payload"
    (Value.as_number (Value.get_method bound "+" 1 env [one]) = 2.);
  let unfinished = Value.uninitialized () in
  check "cannot include uninitialized source"
    (fails (fun () -> Value.add_methods (Value.uninitialized ()) unfinished));
  check "cannot bind uninitialized source"
    (fails (fun () -> ignore (Value.bind env unfinished)));
  check "cannot read uninitialized number"
    (fails (fun () -> ignore (Value.as_number unfinished)));
  Printf.printf "%d bounded-layout storage checks passed\n" !checks
