type t = private {
  offset : int;
  line : int;
  column : int;
  filename : string option;
}

val zero : t
val with_filename : string -> t -> t
val next : char -> t -> t
val to_string : t -> string
val describe : t -> string
