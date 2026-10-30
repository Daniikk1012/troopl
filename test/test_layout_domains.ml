open Troopl

(* A separate process ensures the layout starts unpublished. Each domain owns
   its guest environment and mutable hook state; only internal metadata shares. *)
let () =
  let ready = Atomic.make 0 and start = Atomic.make false in
  let workers = Array.init 4 (fun _ -> Domain.spawn (fun () ->
    let base = Env.make () in
    let count = ref 0 in
    let extension = Value.uninitialized () in
    Value.add_method extension "number" 1 (fun _ args ->
      incr count; List.hd args);
    Value.initialize extension;
    let core = Value.uninitialized () in
    Value.add_method core "extend" 0 (fun _ _ -> extension);
    Value.initialize core;
    let env = Value.uninitialized () in
    Value.add_methods env base;
    Value.add_method env "core" 0 (fun _ _ -> core);
    Value.initialize env;
    Atomic.incr ready;
    while not (Atomic.get start) do Domain.cpu_relax () done;
    for i = 1 to 5000 do
      let number = Builtins.make_number env (float i) in
      let result = Value.invoke_id number (Selector.intern "-" 0) env [] in
      assert (Value.as_number result = -. float i)
    done;
    assert (!count = 10000)) ) in
  while Atomic.get ready < Array.length workers do Domain.cpu_relax () done;
  Atomic.set start true;
  Array.iter Domain.join workers;
  print_endline "4 concurrent first-construction domains; 40000 hooks preserved"
