(** Process-lifetime interned method selectors. Not guest variable bindings. *)

type t = private int

val intern : string -> int -> t
val name : t -> string
val describe : t -> string
