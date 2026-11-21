# Troopl standard library

This is an English, opt-in library implemented in Troopl. The default native
environment stays minimal. Loading the library returns a new environment based
on the one used when loading the standard library.

## Run the demo

```sh
cd stdlib
dune exec troopl -- init.tr
```

It prints:

```text
Hello, Troopl!
15
lazy else-if
🙂я
```

`init.tr` loads the library and executes `main.tr` in the extended environment.
Replace `main.tr` with application code; the loader can remain unchanged.
Both paths are relative to the working directory.

## Load and use

The loader uses the default environment. Whole-file reads return lossless
strings; the source lexer rejects malformed or incomplete UTF-8 during `eval`.

```troopl
Source (fs read "stdlib/stdlib.tr")
(Source ok? then-else [{}] [(crash (Source message))] run)
Loader {() filename "stdlib/stdlib.tr"}
Environment (env run Loader [(eval Source)])
(env run Environment [
  io print ((1 < 2) then ["yes"] else ["no"])
])
```

Extensions compose with the supplied environment's existing `core extend`
methods. No filesystem or IO capability is added if base environment does not
supply it:
standard library requires `core` and `fs`, and operations request other
capabilities only when needed. No global built-in variable names are introduced.

## Added methods

For the list of all methods that the standard library environment provides, see
[STDLIB.pdf](STDLIB.pdf)

## Verification

The library is tested in Troopl itself. `stdlib/test/run.tr` loads it, adds
the assertions `check`, `refute` and `expect` to its environment, and imports
every test file listed there; the first failed assertion crashes with its
label. `dune runtest` runs it, or run it by hand:

```sh
cd stdlib/test
dune exec troopl -- run.tr
```

Only crashes, which Troopl cannot observe, are checked from OCaml
(`test/test_cli.ml`). The original 50 examples remain runnable without
installing this library.
