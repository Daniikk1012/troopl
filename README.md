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
  dune exec troopl
  ```
  To run tests:
  ```sh
  dune runtest
  ```

## Contributing

No rules for now except for [style guide](STYLE.md), since `ocamlformat` is not
used for this project. This might change if this project becomes big enough to
attract a lot of contributors, but is fine for now.

## Language basics

TODO (First need to actually implement everything from the spec)
