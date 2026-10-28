val make_boolean     : Value.t -> bool -> Value.t
val make_number      : Value.t -> float -> Value.t
val make_string      : Value.t -> string -> Value.t

(** Decode host bytes, preserving invalid UTF-8 as negative character codes. *)
val make_byte_string : Value.t -> string -> Value.t

(** Takes ownership of the array; callers must not mutate it afterwards. *)
val make_list        : Value.t -> Value.t array -> Value.t

(** Materialized at/size interface, without the list extension hook. *)
val minimal_list     : Value.t -> Value.t array -> Value.t

val extend           : Value.t -> string -> Value.t -> Value.t
val int_of_value     : Value.t -> int
val size_of_value    : Value.t -> Value.t -> int
val string_of_number : float -> string

(** Lossless by default; strict conversion rejects all negative codes. *)
val string_of_value  : ?lossless:bool -> Value.t -> Value.t -> string
val bytes_of_value   : Value.t -> Value.t -> bytes
val list_of_bytes    : Value.t -> bytes -> Value.t
