# Native environment

Implemented against sections 5.12 and 6.1–6.6 of
`TrOOPL specification-2.pdf`. The older proposal examples are historical:
the accepted API uses `core extend TYPE`, `core tag`, and `core from-seq`,
not `core TYPE extend` or native `strict` methods.

## Capabilities

| Access | Interface |
|---|---|
| `io` | `print String`, `raw-print String`, `read-line`, `error` |
| `io error` | `print String`, `raw-print String` to stderr |
| `fs` | `read Filename`, `write Filename Bytes`, `open-read Filename`, `open-write Filename` |
| Read handle | `read Count`, `close` |
| Write handle | `write Bytes`, `close` |
| `utf-8` | `to-string Bytes`, `from-string String` |
| `env` | `run Environment Block`, `bind Environment Object` |
| `eval Source` | Evaluate UTF-8 source with a fresh lexical scope in the current environment |
| `box Initial` | `get`, `set Value` (returns the box) |
| `array` | `at Index`, `size`, `set Index Value`, `push Value`, `pop` |
| `true`, `false` | Minimal Church booleans, passed through the boolean extension hook |
| `core extend` | `boolean X`, `number X`, `string X`, `list X` |
| `core` | `tag Number`, `from-seq Sequence` |
| `filename` | Current filename as a string |
| `exit Code` | Terminate the process with an integer exit code |
| `crash Message` | Fatal runtime error |

There are no predefined lexical variables. `()` returns the dynamic
environment; `(method ...)` is shorthand for `(() method ...)`.
Unknown variables are lowering errors. The CLI supplies its input filename;
embedding code can use `Env.make ~filename ()` and inject IO channels.

Array `set` and `push` return the array. `pop` returns the removed value.
Arrays retain exactly their five native methods and are not passed through
the list extension hook.

## Fallible operations

IO and filesystem operations return a result object with `ok?`:

- On success, it has the promised type's methods plus `ok?` returning true.
- On failure, it has `ok?` returning false and `message`, but none of the
  promised type's methods.
- Programmer errors (wrong object interface, non-integer index, invalid bytes
  supplied to a writer, etc.) are fatal, not recoverable filesystem failures.

```troopl
Result (fs read "input.bin")
Result ok? then-else [
  io print (Result size to-string)
] [
  io error print (Result message)
] run
```

`print` appends LF and flushes. `raw-print` appends neither LF nor an
explicit flush. Both return an IO result supporting further output methods.
`read-line` strips LF, preserves CR, and returns a failure value at EOF or
for invalid/incomplete UTF-8 input.

Filesystem operations use binary channels: NUL, CRLF, and bytes 128–255 are
preserved. Whole-file `read` materializes a byte list; whole-file `write`
returns an empty-object success result. A writer validates the whole input
before opening/truncating a file.

Handles must be closed explicitly. Read handles return at most the requested
count and at most 64 KiB per read. Reading zero bytes returns an empty list;
an empty result from a positive-sized read indicates EOF. Writes return a
write-handle result. Close returns an empty-object result; double close and
operations on closed handles return failures. Streaming writes are buffered;
OS failures may be reported during write or close. The library's text helpers
use whole-file operations.

Paths are interpreted by the host filesystem relative to the process working
directory. No renaming, deleting, directory listing, metadata, or primitive
import operations are added: these are not specified environment methods.

## UTF-8

`from-string` consumes only `size` and `at`, validates Unicode scalar
values, and returns a materialized byte list. Invalid string values are fatal.

`to-string` consumes a minimal byte list and returns:

- Complete input: a string success result with an empty `remainder`.
- A valid unfinished final scalar: a string success result containing only
  the complete prefix; `remainder` delegates to the original list starting
  at the unfinished scalar.
- Invalid input: a failure with `message`, `index`, and `byte` methods.
  The index is the zero-based position of the offending byte.

Overlong encodings, surrogate encodings, out-of-range scalars, stray
continuations, and invalid continuation bytes are rejected. The remainder is
not copied and may observe mutations in its source. File text helpers reject
an incomplete final scalar rather than silently dropping it.

## Core and sequences

Default extension methods are identity functions. Literal numbers and strings,
and builtin-produced numbers, booleans, strings, and strict lists, are passed
through the active environment's corresponding extension hook. A missing
`core` or extension fails when that builtin is constructed.

Strings store Unicode code points, not Java UTF-16 units. Their character
numbers and size number are constructed ahead of time and returned unchanged
on repeated access. Strict lists likewise retain their elements and size value.

`core tag N` returns an initialized object with no methods and only N's
numeric representation. It deliberately does not invoke an extension hook.

`core from-seq S` repeatedly calls `S run`. A node has `cons?`; true
nodes additionally have `get` and `next`. A false node needs neither.
The boolean is consumed by selecting and running branches with `then-else`,
not by probing an internal boolean representation. The resulting list is
strict and goes through `core extend list`.

## Diagnostics

Calls, literal construction, and object inclusion update a single current
location per OCaml domain. Native callbacks resume the native operation's
location after successful guest calls; errors inside guest calls keep their
own expression position. No exception handler or trace frame is pushed for
every guest call, and tail-call annotations are checked at compilation.

On a runtime error, the filename is read by calling the active environment's
`filename` method and reconstructing its string through `size`/`at`.
If absent, invalid, or failing, the lexical source filename is used (or
`<unknown>` when no source name exists). Reporting uses a recursion guard.
A captured native filename can still be read when `core` is missing, using
internal numeric-tag indices solely for that diagnostic fallback.

The CLI prints `filename:line:column: CATEGORY: message`, exits with status 1
for lexer/parser/lowering/runtime/file-open errors, and leaves successful
output on stdout. `eval` uses the current filename and a fresh lexical scope.
Derived stdlib import overrides the filename with the module path and binds
returned methods to that module environment.

The routine tests include filename overrides/fallbacks, imported module
locations, malformed source, real subprocess exit statuses, IO/file/UTF-8
successes and failures, a 100,000-node sequence, and a million-iteration loop.
