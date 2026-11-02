type t
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

(** Primitive constructors run every applicable dynamic extension hook.
    Kept with dispatch to avoid a Value/Builtins initialization cycle. *)
val extend : t -> Selector.t -> t -> t
val make_number : t -> float -> t
val make_boolean : t -> bool -> t
val make_string : t -> string -> t
val make_byte_string : t -> string -> t
val int_of_value : t -> int
