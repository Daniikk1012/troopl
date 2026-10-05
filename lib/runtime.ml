(* TODO: Report error positions for builtin functions instead of Position.zero.
         Perhaps using stack traces?
         Not sure, we need to be careful not to break tail recursion and keep
         memory usage reasonable *)

exception Error of string * Position.t
