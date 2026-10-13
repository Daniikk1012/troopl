val make_boolean : Value.t -> bool -> Value.t
val make_number : Value.t -> float -> Value.t
val make_string : Value.t -> string -> Value.t
val make_list : Value.t -> Value.t array -> Value.t
val extend : Value.t -> string -> Value.t -> Value.t
val int_of_value : Value.t -> int
val size_of_value : Value.t -> Value.t -> int
val string_of_number : float -> string
val string_of_value : Value.t -> Value.t -> string
val filename : Value.t -> string -> string
val set_environment : Value.t -> unit
val locate : Value.t -> Position.t -> unit
val bytes_of_value : Value.t -> Value.t -> bytes
val list_of_bytes : Value.t -> bytes -> Value.t
