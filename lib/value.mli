type t
type number_layout
val create_number_layout :
  (Selector.t * (float -> t -> t list -> t)) array -> number_layout
val number_from_layout : number_layout -> float -> t
val invoke_id : t -> Selector.t -> t -> t list -> t

val uninitialized      : unit -> t
val set_number         : t -> float -> unit
val as_number          : t -> float
val add_method         : t -> string -> int -> (t -> t list -> t) -> unit
val add_method_id      : t -> Selector.t -> (t -> t list -> t) -> unit
val add_methods        : t -> t -> unit
val get_method         : t -> string -> int -> t -> t list -> t
val get_method_id      : t -> Selector.t -> t -> t list -> t
val initialize         : t -> unit
val finish             : t -> t
val empty              : unit -> t
val bind               : ?before:(unit -> unit) -> t -> t -> t
val ensure_initialized : t -> unit
val storage_depth      : t -> int
(** Diagnostic representation depth, bounded by eight; not guest-visible. *)
val to_string          : t -> string
