type t = private { offset : int; line : int; column : int }

val zero      : t
val next      : char -> t -> t
val to_string : t -> string
