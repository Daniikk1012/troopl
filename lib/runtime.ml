(** A single location per OCaml domain, not a call-stack trace. Setting it
    before dispatch leaves guest tail calls in tail position. *)

exception Error of string * Position.t

(* The filename is computed only when an error is reported, from [source]
   (the active environment) by a static function. Locating therefore
   allocates one small record and no closure. Mutating a long-lived record
   instead would be slower: every write goes through the write barrier. *)
type context =
  | Context : {
      position : Position.t;
      source : 'source;
      filename : 'source -> string -> string;
      reporting : bool;
    }
      -> context

let initial =
  Context
    {
      position = Position.zero;
      source = ();
      filename = (fun () fallback -> fallback);
      reporting = false;
    }

let context = Domain.DLS.new_key (fun () -> initial)
let current () = Domain.DLS.get context
let position () = match current () with Context { position; _ } -> position

let set_location position source filename =
  match current () with
  | Context { reporting; _ } ->
      Domain.DLS.set context (Context { position; source; filename; reporting })

let set_environment source filename =
  match current () with
  | Context { position; reporting; _ } ->
      Domain.DLS.set context (Context { position; source; filename; reporting })

let protect f =
  let previous = current () in
  Fun.protect ~finally:(fun () -> Domain.DLS.set context previous) f

(* Native operations resume their own location after a successful guest
   callback. Failures inside the callback keep the callback's location. *)
let resume f =
  let saved = current () in
  let result = f () in
  Domain.DLS.set context saved;
  result

let error message =
  let saved = current () in
  let (Context { position; source; filename; reporting }) = saved in
  let fallback = Option.value position.filename ~default:"<unknown>" in
  let name =
    if reporting then fallback
    else
      Fun.protect
        ~finally:(fun () -> Domain.DLS.set context saved)
        (fun () ->
          Domain.DLS.set context
            (Context { position; source; filename; reporting = true });
          try filename source fallback with _ -> fallback)
  in
  raise (Error (message, Position.with_filename name position))
