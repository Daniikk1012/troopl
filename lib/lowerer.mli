type lowered = { ir : Ir.t; scope_size : int }

exception Error of string * Position.t

(** The unoptimized mode is an executable reference for differential tests. *)
val lower : ?optimize:bool -> Expression.t -> lowered
