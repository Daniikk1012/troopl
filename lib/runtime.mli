(** Bounded per-domain diagnostic state, preserving guest tail calls. *)
exception Error of string * Position.t

val position        : unit -> Position.t
val set_location    : Position.t -> (unit -> string) -> unit
val set_environment : (unit -> string) -> unit
val protect         : (unit -> 'a) -> 'a
val resume          : (unit -> 'a) -> 'a
val error           : string -> 'a
