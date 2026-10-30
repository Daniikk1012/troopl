# Shared method storage follow-up

Measured 2026-10-30. This remains an independent experimental branch,
`codex/shared-layout-overlays`, based on `codex/prototype-shared-layouts`.
It does not merge the layout prototype into production or include the
separate optional language-capability branches.

## Representation and semantics

Native numbers keep the original prototype's immutable selector/code layout
and lexical numeric capture. Completed method storage can now be shared by
inclusion and environment binding. Ordinary methods are stored as raw OCaml
callables, without a per-method variant wrapper. Empty objects defer table
allocation until their first method is added.

An object under construction owns its current table or overlay delta. An
inclusion freezes that storage under a sharing/merge node; subsequent method
definitions write into a fresh delta. Completed source objects are immutable.
Later inclusions and definitions still win. Numeric tags remain independent
of method captures: `A 1 B {A (core tag 99)} B + 1` returns 2.
No implicit self/receiver is introduced.

Storage depth is capped at eight. Deeper inclusion/binding combinations are
flattened into a table. Each flattened callable captures only its effective
method payload and bound environment, rather than the obsolete storage chain.
This allows overwritten captured data to be collected. Flattening costs a
table and can materialize bound numeric callables; it is a bounded-overlay
strategy, not a general V8/Lua shape engine or inline-cache implementation.

Environment binding shares one wrapper over the original storage. Nested
bindings preserve callback order and the original method's environment.
Missing methods fail before binding callbacks execute. Both ordinary lookup
and the interpreter's direct dispatch preserve initialization checks.

Numeric layout publication uses an atomic option and a mutex with a second
check after locking. Only immutable internal code descriptors are constructed
under that lock. Every literal still calls the active custom extension hook;
there is no default-core bypass or arbitrary result cache. OCaml explicitly
documents that [Lazy.force is not concurrency-safe](https://ocaml.org/manual/5.3/api/Lazy.html);
[Atomic](https://ocaml.org/manual/5.3/api/Atomic.html) publishes the completed
layout. This does not make mutable guest arrays/boxes domain-safe.

## Revisions and method

- Production: `fc4f132`.
- Original shared numeric layouts: `ab5eabe`.
- Refined storage: `deff367` (includes harness commit `a237c1c`).

OCaml 5.3.0 native, Dune 3.24.0, Cygwin on Windows. Native Windows and Linux
were not tested. Each implementation uses the identical
[`test/benchmark_layout.ml`](../test/benchmark_layout.ml) harness, including
the same executable stanza/module exclusion in `test/dune` for baseline
exports. Parsing, lowering, builds, library loading and calculator input-string
construction are outside the timed region.

Each workload warms once and reports the median of five samples, with full
major GC before each sample. Allocation is cumulative bytes per unit, sampled
over the same operation as timing. Run order was production/prototype/overlays,
then overlays/prototype/production; implementations did not run concurrently.
The final full regression suite ran after the timed matrix.

These are local measurements with no confidence intervals or platform-wide
claim. Timing spread matters, especially for short operations. The two
independent median batches are shown below; they are not error bounds.

## Timings

Seconds per batch, first / reversed run order.

| Workload | Units | Production | Original layouts | Refined overlays |
| --- | ---: | ---: | ---: | ---: |
| Native number construction | 20,000 | .010194 / .009745 | .001731 / .001748 | .001693 / .001632 |
| Actual stdlib number construction | 20,000 | .034556 / .034236 | .025841 / .026012 | .020091 / .019914 |
| Two custom inclusion layers | 20,000 | .041408 / .041380 | .033532 / .032869 | .021041 / .016910 |
| Include an existing number | 50,000 | .022891 / .022486 | .022647 / .022735 | .002063 / .001849 |
| Construct eight guest methods | 50,000 | .012561 / .012665 | .013108 / .013045 | .014729 / .013270 |
| Embedding numeric callable lookup | 1,000,000 | .049275 / .048931 | .012927 / .012979 | .012136 / .011879 |
| Bind an existing number | 20,000 | .008767 / .008726 | .009240 / .009300 | .000188 / .000178 |
| Actual stdlib calculator | 1,000 | 1.723272 / 1.715183 | 1.578703 / 1.573544 | 1.451140 / 1.455248 |

The calculator repeatedly evaluates `2 + 3 * 4`, creating a fresh session
per sample and accumulating 1,000 history entries. It exercises the real
Troopl parser and stdlib code, but covers only one calculator input shape.

Compared with the original prototype, stdlib number construction is about
22-23% faster and the calculator about 8% faster. Relative to production,
calculator time is about 15-16% lower. Sharing existing numeric storage is
much cheaper than copying all 18 method entries for inclusion or binding.
These microbenchmark ratios do not imply the same application speedup.

Generic eight-method construction remains a regression: about 5-17% slower
than production across these batches, and 2-12% slower than the old prototype.
Removing wrapper allocation did not establish a generic-object timing win.
The prototype should stay separate pending broader workload/platform evidence.

## Cumulative allocation

Bytes per unit, rounded; both run orders agree apart from baseline overhead.
This is allocation during the operation, not retained heap or RSS.

| Workload | Production | Original layouts | Refined overlays |
| --- | ---: | ---: | ---: |
| Native number | 2232 | 400 | 352 |
| Stdlib number | 4584 | 3264 | 2072 |
| Two inclusion layers | 6104 | 4848 | 2784 |
| Include existing number | 1104 | 1568 | 296 |
| Eight guest methods | 1152 | 1296 | 1168 |
| Embedding numeric lookup | 16 | 96 | 48 |
| Bind existing number | 1936 | 2688 | 72 |
| Calculator expression | 3664450 | 3326473 | 2761848 |

The calculator allocates about 17% less than the original layout prototype
and 25% less than production. Generic construction is close to production
allocation, but still 16 bytes higher per object. Embedding retrieval halves
the old prototype's allocation yet remains three times production: returning
a bound callable still needs a closure. Interpreter dispatch uses `invoke_id`
and does not create that embedding callable on every call.

A preliminary run caught a lookup regression (~48 ms per million) caused by
an accidentally polymorphic search helper. `ocamlc -i` confirmed a generic key
type; annotating it with `number_layout` and `Selector.t` restored integer
comparisons. All tables/CSVs here are from the corrected revision and a fresh
complete matrix, not the preliminary measurements.

## Retained heap

Separate measurement: keep 10,000 newly constructed objects in an array,
perform full major GC, and subtract baseline live words. The array stays
rooted through measurement. Values below include the array's eight-byte slot
per object and small shared overhead. Existing source objects, stdlib and
internal layouts are rooted before baseline sampling. This is live managed
heap, not peak memory or OS RSS; both run orders gave identical values.

| Retained workload | Production bytes/object | Original layouts | Refined overlays |
| --- | ---: | ---: | ---: |
| Native number | 1768.00 | 96.00 | 96.00 |
| Stdlib number | 2944.00 | 1768.00 | 752.00 |
| Include existing number | 800.97 | 1248.99 | 73.07 |
| Bind existing number | 1815.92 | 2551.99 | 80.00 |

Sharing intentionally retains reachable original method captures. It does not
promise to prune a small overlay before the depth limit. A separate weak-ref
regression replaces a method capturing an 8 MiB buffer through 40 generations
and confirms flattening releases that overwritten buffer.

## Validation and reproduction

```sh
dune build @install
dune runtest --force
dune exec test/benchmark_layout.exe
dune exec test/benchmark_layout.exe -- --retained
```

Run from the repository root. For comparisons, export the exact baseline
revisions into separate directories and copy this same harness/stanza into
each; do not compare against a different historical harness.

The full suite passed after the final matrix: 199 v0.1 checks, 52 v0.2 checks,
96 environment/diagnostic checks, 50 stdlib checks, 173 calculator checks,
all 50 examples, CLI/frontend/evaluator checks, 30 optimization checks,
eight original layout checks and 220 new storage checks. A separate process
starts four domains at first numeric construction and confirms all 40,000
custom number-hook invocations occur while sharing layout publication.

Raw timing and retained-heap CSVs are in [`layout-overlays/`](layout-overlays/).
The implementation is intentionally not merged with the capability prototypes
or the narrow pure-hook-cache experiment.
