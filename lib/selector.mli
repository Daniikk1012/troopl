(** Process-lifetime interned method selectors. Not guest variable bindings. *)
type t = private int
val intern : string -> int -> t
val describe : t -> string
val fresh : string -> int -> t
