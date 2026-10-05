val make_boolean : Value.t -> bool   -> Value.t
val make_number  : Value.t -> float  -> Value.t
val make_string  : Value.t -> string -> Value.t

(* Not sure if these should be defined in this module *)
val int_of_value     : Value.t -> int
val string_of_number : float -> string
