type t

val uninitialized : unit -> t
val set_number    : t -> float -> unit
val as_number     : t -> float
val add_method    : t -> string -> int -> (t -> t list -> t) -> unit
val add_methods   : t -> t -> unit
val get_method    : t -> string -> int -> t -> t list -> t
val initialize    : t -> unit
val to_string     : t -> string
