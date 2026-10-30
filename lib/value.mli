type t

val uninitialized      : unit -> t
val set_number         : t -> float -> unit
val as_number          : t -> float
val add_method         : t -> string -> int -> (t -> t list -> t) -> unit
val add_method_id      : t -> Selector.t -> (t -> t list -> t) -> unit
val add_methods        : t -> t -> unit
val get_method         : t -> string -> int -> t -> t list -> t
val get_method_id      : t -> Selector.t -> t -> t list -> t
val find_method_id     : t -> Selector.t -> (t -> t list -> t) option
val initialize         : t -> unit
val finish             : t -> t
val empty              : unit -> t
val bind               : ?before:(unit -> unit) -> t -> t -> t
val ensure_initialized : t -> unit
val to_string          : t -> string
