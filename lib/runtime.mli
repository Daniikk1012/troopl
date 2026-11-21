(** Bounded per-domain diagnostic state, preserving guest tail calls. *)

exception Error of string * Position.t

val position : unit -> Position.t

val set_location :
  Position.t -> 'source -> ('source -> string -> string) -> unit
(** [set_location position source filename]: on error, the reported filename is
    [filename source fallback], where [fallback] comes from [position]. *)

val set_environment : 'source -> ('source -> string -> string) -> unit
val protect : (unit -> 'a) -> 'a
val resume : (unit -> 'a) -> 'a
val error : string -> 'a
