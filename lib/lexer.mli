type t

exception Error of string * Position.t

val create     : string -> t
val next_token : t -> Token.t
