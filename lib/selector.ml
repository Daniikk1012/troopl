type t = int

(* IDs live as long as the interpreter. Never recycle an ID while an IR or
   object can still refer to it. The mutex also covers embedded domains. *)
let registry = Hashtbl.create ~random:true 128
let descriptions = Dynarray.create ()
let mutex = Mutex.create ()

let intern name arity =
  if arity < 0 then invalid_arg "negative method arity";
  Mutex.lock mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock mutex) (fun () ->
    match Hashtbl.find_opt registry (name, arity) with
    | Some id -> id
    | None ->
        let id = Dynarray.length descriptions in
        Dynarray.add_last descriptions (name, arity);
        Hashtbl.add registry (name, arity) id;
        id)

let describe id =
  Mutex.lock mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock mutex) (fun () ->
    let name, arity = Dynarray.get descriptions id in
    name ^ "/" ^ string_of_int arity)

let fresh label arity =
  if arity < 0 then invalid_arg "negative method arity";
  Mutex.lock mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock mutex) (fun () ->
    let id = Dynarray.length descriptions in
    Dynarray.add_last descriptions (label, arity);
    id)
