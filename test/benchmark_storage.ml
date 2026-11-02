open Troopl

let marker = Value.empty ()
let method_ _ _ = marker
let measure name units f =
  ignore (f ());
  let samples = List.init 5 (fun _ ->
    Gc.full_major ();
    let before = Gc.allocated_bytes () and start = Unix.gettimeofday () in
    let result = f () in
    let seconds = Unix.gettimeofday () -. start in
    let bytes = Gc.allocated_bytes () -. before in
    ignore (Sys.opaque_identity result);
    seconds, bytes) |> List.sort compare in
  let seconds, bytes = List.nth samples 2 in
  Printf.printf "%s,%d,%.6f,%.2f\n%!" name units seconds (bytes /. float units)

let build selectors updates =
  let source = Value.uninitialized () in
  Array.iter (fun key -> Value.add_method_id source key method_) selectors;
  let result = ref (Value.finish source) in
  for i = 1 to updates do
    let next = Value.uninitialized () in
    Value.add_methods next !result;
    Value.add_method_id next selectors.(i mod Array.length selectors) method_;
    result := Value.finish next
  done;
  !result

let () =
  print_endline "workload,units,median_seconds,allocated_bytes_per_unit";
  List.iter (fun width ->
    let selectors = Array.init width (fun i ->
      Selector.intern ("storage-" ^ string_of_int i) 0) in
    measure (Printf.sprintf "override-%d" width) 2000
      (fun () -> build selectors 2000);
    let object_ = build selectors 2000 in
    let calls = 100000 in
    measure (Printf.sprintf "lookup-%d" width) calls (fun () ->
      for i = 0 to calls - 1 do
        assert (Value.invoke_id object_ selectors.(i mod width) marker []
          == marker)
      done;
      object_)) [8; 64; 512];
  let empty = Value.empty () in
  measure "bind-chain" 2000 (fun () ->
    let value = ref empty in
    for _ = 1 to 2000 do value := Value.bind marker !value done;
    !value)
