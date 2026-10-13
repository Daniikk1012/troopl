# Troopl standard library

This is an English, opt-in library implemented in Troopl. The default native
environment stays minimal. Loading the library returns a factory; calling
`extend E` builds an environment by including `E` and overriding its extension
hooks, as in the environment-wrapper pattern.

## Run the demo

From the repository root:

```sh
dune exec troopl -- stdlib/demo.tr
```

It prints:

```text
Hello, Troopl!
15
lazy else-if
🙂я
```

## Load and use

The loader uses only the default environment. It checks the file and UTF-8
results before evaluation; incomplete UTF-8 is not silently accepted.

```troopl
Bytes (fs read "stdlib/stdlib.tr")
(Bytes ok? then-else [{}] [(crash (Bytes message))] run)
Source (utf-8 to-string Bytes)
(Source ok? then-else [{}] [(crash (Source message))] run)
(Source remainder size = 0 then-else [{}] [
  crash "incomplete UTF-8 standard library"
] run)
Loader {() filename "stdlib/stdlib.tr"}
Stdlib (env run Loader [(eval Source)])
Environment (Stdlib extend ())
(env run Environment [
  io print ((1 < 2) then ["yes"] else ["no"])
])
```

Extensions compose with the supplied environment's existing `core extend`
methods. No filesystem or IO capability is added if `E` does not supply it:
`extend E` requires `E core` and `E fs`, and operations request other
capabilities only when needed. No global built-in variable names are introduced.

## Added methods

| Receiver | Methods |
|---|---|
| Boolean | `not`, `and B`, `or B`, `xor B`, `and-then Block`, `or-else Block`, `then Block`, `to-string` |
| Conditional chain | `else Block`, `else-if TestBlock BranchBlock`, `end` |
| Number | `abs`, `min N`, `max N` |
| List | `is-empty`, `+ L`, `map F`, `filter P`, `fold F Seed`, `for-each F`, `to-seq`, `strict` |
| String | List conveniences plus string `+ S`, `substring Start Stop`, `reverse`, `equals S`, `to-string`, `strict` |
| Environment `list` | `range Start Stop`, `from L`, `from-minimal L`, `of` |
| List builder | `and X`, `end` |
| Environment `string` | `from S`, `from-minimal S` |
| Environment `fs` | Native methods plus `read-text F`, `write-text F S` |
| Environment | `import F`, `import E F` |

`else-if` takes a **test block**, not an already computed boolean, so tests
after a successful branch are never evaluated. Branches execute when `else`
or `end` is called. `end` uses the empty block, whose result is the current
environment if no branch is selected.

List mapping and concatenation are lazy views. Filtering, `list from`,
builder `end`, and list `strict` materialize through `core from-seq`.
`fold` takes a `run/2` function, and `map`, `filter`, and `for-each`
take a `run/1` function. Views may observe later mutation in their source.
`list from` gives a snapshot; `from-minimal` preserves delegation.

Ranges are start-inclusive and stop-exclusive. Substrings use the same bounds
convention and reject invalid indices. String `strict` materializes Unicode
characters through the UTF-8 capability. Native arrays keep only their five
minimal/mutation methods; use `list from Array` for a snapshot or
`list from-minimal Array` for a list view.

## Text files and modules

`fs read-text` and `fs write-text` return the same `ok?` result protocol
as native filesystem methods. `read-text` preserves CRLF in file contents,
propagates invalid-byte details, and rejects incomplete final UTF-8 sequences.

`import F` reads and evaluates a module using the current environment.
`import E F` uses the supplied environment. Both install `filename F` in
the module environment and bind every returned method to that environment.
Import is a Troopl method, not a new interpreter primitive.
The importer uses its caller's filesystem/evaluation capabilities; the supplied
module environment need not expose `eval` or `fs` to the module.
It still needs the appropriate `core` hooks for builtin construction,
including the numeric index values used while consuming source strings.

Paths are resolved by the host filesystem relative to the process working
directory; this library does not introduce module-relative path resolution,
caching, a package manager, or implicit module loading. Pass explicit paths
when importing from different directories. File errors during import crash
with the returned failure message.

## Verification

`dune runtest` covers control-flow laziness, string/list operations, views
versus snapshots, file helpers, imported environments, and module diagnostics.
The original 50 examples remain runnable without installing this library.
