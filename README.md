# TrOOPL - OCaml interpreter

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

The package requires OCaml 5.3 or newer and Dune 3.24 or newer. Verification
uses OCaml 5.3.0 and Dune 3.24.0. Earlier OCaml releases are not supported by
the package metadata.

## Contributing

No rules for now except for [style guide](STYLE.md), since `ocamlformat` is not
used for this project. This might change if this project becomes big enough to
attract a lot of contributors, but is fine for now.

Source files and their responsibilies:

| Source              | Responsibility                          |
|---------------------|-----------------------------------------|
| `bin/main.ml`       | Entry point of the program              |
| `lib/builtins.ml`   | Description of builtin types            |
| `lib/env.ml`        | Description the default environment     |
| `lib/encoding.ml`   | UTF-8 conversion and lazy remainders     |
| `lib/filesystem.ml` | Byte-file and streaming capabilities    |
| `lib/outcome.ml`    | Recoverable success/failure objects      |
| `lib/utf8.ml`       | UTF-8 scalar validation and decoding     |
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

See [the 50 runnable examples](examples/README.md) for language basics,
object composition, recursion, dynamic environments, and conveniences
implemented in Troopl rather than as native built-ins.

Run one from the repository root:

```sh
dune exec troopl -- examples/example_01.tr
```

Every example prints its result. `dune runtest` checks all 50 returned values
and their exact output, alongside the existing interpreter tests.

## Environment and standard library

The [native environment](doc/ENVIRONMENT.md) implements the interfaces from
`TrOOPL specification-2.pdf`, sections 5.12 and 6.6: byte filesystem access,
UTF-8 conversion, IO, dynamic environments, evaluation, mutable boxes/arrays,
builtin extensions, filenames, exit, and crash.

The [English standard library](stdlib/README.md) is opt-in and written in
Troopl. It supplies boolean control flow, string/list operations, text-file
helpers, and module import using the environment-wrapper pattern.

```sh
dune exec troopl -- stdlib/demo.tr
```

Errors print `filename:line:column: category: message` to stderr and exit
with status 1. Runtime filenames come from the active environment's
`filename` method, with a source-filename fallback if it is missing or invalid.
Position tracking uses bounded per-domain state and preserves guest tail calls.
