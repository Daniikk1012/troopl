(** Runtime locations and filenames supplied by the active environment. *)
val filename        : Value.t -> string -> string
val set_environment : Value.t -> unit
val locate          : Value.t -> Position.t -> unit
