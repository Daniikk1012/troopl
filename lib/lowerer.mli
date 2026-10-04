type lowered = { ir : Ir.t; scope_size : int }

exception Error of string * Position.t

val lower : Expression.t -> lowered
