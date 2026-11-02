(** Eager, immutable descriptors for the specification's numeric methods.
    No guest value or extension hook is evaluated during initialization. *)
type operation =
  | Unary of (float -> float)
  | Binary of (float -> float -> float)
  | Comparison of (float -> float -> bool)
  | To_string
val mem : Selector.t -> bool
val find : Selector.t -> operation
val iter_selectors : (Selector.t -> unit) -> unit
val string_of_number : float -> string
val int_of_number : float -> int
