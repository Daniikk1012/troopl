# TrOOPL - OCaml intepreter

TrOOPL is an object-oriented language in which values expose methods identified
by their name and arity. Objects can include other objects, methods capture
lexical variables, and capabilities are supplied through a dynamic environment.

## Building and running

1. Set up `opam` and `dune` - https://ocaml.org/docs/installing-ocaml
2. To build:
  ```sh
  dune build
  ```
  To build & run:
  ```sh
  dune exec troopl [troopl args]
  ```
  To run tests:
  ```sh
  dune runtest
  ```

As of right now, we haven't tested which OCaml versions work with this project,
therefore we do not give a concrete minimal version. 5.3.0 works at the very
least.

## Contributing

No rules for now except for [style guide](STYLE.md), since `ocamlformat` is not
used for this project. This might change if this project becomes big enough to
attract a lot of contributors, but is fine for now.

Source files and their responsibilies:

| Source              | Responsibility                          |
|---------------------|-----------------------------------------|
| `bin/main.ml`       | Entry point of the program              |
| `lib/builtins.ml`   | Description of builtin types            |
| `lib/evaluator.ml`  | Evaluator for the IR                    |
| `lib/expression.ml` | Description of the AST                  |
| `lib/ir.ml`         | Description of the IR                   |
| `lib/lexer.ml`      | String -> token stream lexer            |
| `lib/lowerer.ml`    | AST -> IR lowerer                       |
| `lib/parser.ml`     | Token stream -> AST parser              |
| `lib/position.ml`   | Description of the source position type |
| `lib/runtime.ml`    | Common runtime definitions              |
| `lib/token.ml`      | Description of a token                  |
| `lib/value.ml`      | Description of a runtime value          |
| `test/*.ml`         | Automatic tests                         |

## Language basics

TODO (First need to actually implement everything from the spec)
