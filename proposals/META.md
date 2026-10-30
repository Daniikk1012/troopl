# Opt-in metaprogramming capability

Proposal 7.3 extension, not a change to the v0.2 default environment.
Run a program with `dune exec troopl -- --experimental program.tr`.
Embedders can use `Experimental.extend (Env.make ())`.

- `meta new-method Name Arity Source`: aliases Source's run/Arity binding.
- `meta invoke Target Name Arguments`: calls a dynamically named method;
  Arguments is consumed using size and at in ascending index order.

Names use lossless string conversion; arities must be finite nonnegative
integers. Initialization and missing-method errors remain fatal. Target
initialization is checked before consuming the argument list. The method is
resolved after materializing arguments. Index numbers use active core hooks.
Original lexical captures and env-bind wrappers are preserved. No implicit
self, builtin variables, parser changes or source-code generation are used.
