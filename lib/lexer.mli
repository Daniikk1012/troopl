type t

exception Error of string * Position.t

val create     : ?filename:string -> string -> t
val next_token : t -> Token.t
