(** A single location per OCaml domain, not a call-stack trace. Setting it
    before dispatch leaves guest tail calls in tail position. *)
exception Error of string * Position.t

type context = {
  position : Position.t;
  filename : unit -> string;
  reporting : bool;
}

let initial = {
  position = Position.zero;
  filename = (fun () -> "<unknown>");
  reporting = false;
}
let context = Domain.DLS.new_key (fun () -> initial)
let current () = Domain.DLS.get context
let position () = (current ()).position
let set_location position filename =
  let previous = current () in
  Domain.DLS.set context { position; filename; reporting = previous.reporting }
let set_environment filename =
  let previous = current () in
  Domain.DLS.set context { previous with filename }

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
  let fallback =
    Option.value saved.position.filename ~default:"<unknown>"
  in
  let filename =
    if saved.reporting then fallback else
      Fun.protect
        ~finally:(fun () -> Domain.DLS.set context saved)
        (fun () ->
          Domain.DLS.set context { saved with reporting = true };
          try saved.filename () with _ -> fallback)
  in
  raise (Error (message, Position.with_filename filename saved.position))
