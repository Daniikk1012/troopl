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

Run a file with program arguments:

```sh
dune exec troopl -- path/to/program.tr argument-one "argument two"
```

`system args` includes the entry-point filename followed by these arguments.
The v0.2 signal-exit conversion uses a small C stub and needs the C toolchain
normally installed with OCaml.

Run the opt-in timing/allocation benchmarks separately from correctness tests:

See [committed performance results and prototype comparisons](benchmarks/RESULTS.md).

```sh
dune exec test/benchmark.exe
```

The harness excludes parsing, warms each workload, and reports the median of
three runs. Allocation is cumulative, not resident memory. OCaml's native
runtime may report zero for the GC stack-size field; it is not a stack proof.

## Contributing

No rules for now except for [style guide](STYLE.md), since `ocamlformat` is not
used for this project. This might change if this project becomes big enough to
attract a lot of contributors, but is fine for now.

Source files and their responsibilies:

| Source               | Responsibility                          |
|----------------------|-----------------------------------------|
| `bin/main.ml`        | Entry point of the program              |
| `lib/builtins.ml`    | Description of builtin types            |
| `lib/env.ml`         | Description the default environment     |
| `lib/encoding.ml`    | Lossless UTF-8 byte conversion          |
| `lib/filesystem.ml`  | Byte-file and streaming capabilities    |
| `lib/outcome.ml`     | Recoverable success/failure objects     |
| `lib/utf8.ml`        | UTF-8 scalar validation and decoding    |
| `lib/system.ml`      | Process execution, time, and exit       |
| `lib/evaluator.ml`   | Evaluator for the IR                    |
| `lib/expression.ml`  | Description of the AST                  |
| `lib/ir.ml`          | Description of the IR                   |
| `lib/lexer.ml`       | String -> token stream lexer            |
| `lib/lowerer.ml`     | AST -> IR lowerer                       |
| `lib/parser.ml`      | Token stream -> AST parser              |
| `lib/position.ml`    | Description of the source position type |
| `lib/runtime.ml`     | Common runtime definitions              |
| `lib/token.ml`       | Description of a token                  |
| `lib/value.ml`       | Description of a runtime value          |
| `test/*.ml`          | Automatic tests                         |

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

For complete understanding of the language, see
[the specification](SPECIFICATION.pdf).

## Environment and standard library

Native interfaces are described in the specification. Implementation details:

- Process commands are argument vectors, without an implicit shell. Signal
  termination reports the negative native signal number.
- Process IO uses concurrent pipe readers on every platform, without
  temporary files or a separate platform-specific IO implementation.
  Captured output is materialized in memory, not streamed to Troopl.
- Directory entries are sorted by byte order. Rename replacement behavior
  follows the host OS; working-directory changes affect the whole process.

The [English standard library](stdlib/README.md) is opt-in and written in
Troopl. It supplies boolean control flow, string/list operations, text-file
helpers, and module import using the environment-wrapper pattern.

```sh
dune exec troopl -- stdlib/init.tr
```

Errors print `filename:line:column: category: message` to stderr and exit
with status 1. Runtime filenames come from the active environment's
`filename` method, with a source-filename fallback if it is missing or invalid.
Position tracking uses bounded per-domain state and preserves guest tail calls.
File-opening and reading errors report the filename without a source position.

## Calculator application

The [calculator](examples/calculator/README.md) is a larger application written
in Troopl: an expression parser, variables, functions, history, session files,
filesystem inspection, and explicit command execution.

```sh
dune exec troopl -- examples/calculator/main.tr
```

The calculator parses its own input language; it does not evaluate user input
as Troopl source. The test suite covers the original 50 examples, Version 0.1
capabilities, and calculator arithmetic, error recovery, persistence, and CLI IO.

## Shared-storage experiment

This branch refines the shared numeric layout prototype with bounded method
overlays for inclusion and environment binding. It preserves custom literal
hooks and lexical method captures, with no implicit self. See the
[benchmark and validation report](benchmarks/SHARED_LAYOUT_OVERLAYS.md) for
architecture, reproducible measurements and remaining regressions. This
experimental representation has not been merged into production.
