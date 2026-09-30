type kind = OpenParen  | CloseParen
          | OpenBlock  | CloseBlock
          | OpenObject | CloseObject
          | Number   of float
          | String   of string
          | Variable of string
          | Method   of string

type t = { kind : kind; pos : Position.t }

val string_of_kind : kind -> string
val to_string      : t -> string
