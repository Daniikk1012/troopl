# Selector, capture and prototype benchmark results

Measured 2026-10-29. These results are tracked, unlike local doc/ notes.
No default-core shortcut or arbitrary hook-result memoization is included.

## Implementations

| Build | Code commit | Branch |
| --- | --- | --- |
| v0.2 reference | 0de2eb6 | saved baseline |
| Selector/capture optimizations | d25e87b | codex/spec-v01-calculator |
| Shared numeric layout prototype | 2950dd0 | codex/prototype-shared-layouts |
| Pure-hook cache prototype | 7a6c433 | codex/prototype-pure-hook-cache |

Later production commits add the same pure-hook comparison harness and an
executable reference path for differential tests; optimized execution is
unchanged. Prototype branches are independent siblings, not cumulative.

The baseline was exported into a temporary directory and given exactly the
expanded test/benchmark.ml harness. It includes v0.2 behavior before selectors
or capture changes. Branches and code are committed locally; nothing pushed.

## Production changes

Methods are interned by the complete (name, arity) selector. Executable calls
and native hot paths use the integer ID, with reverse names for diagnostics.
Native arithmetic selector/operation registration is hoisted out of constructors.
String-based embedding APIs remain but perform interning; performance-sensitive
embedders should cache Selector.intern and use the ID API.

The process-lifetime registry is mutex-protected, and IDs are never recycled.
Repeated untrusted eval can grow this metadata; per-session registries or
bounded loading policies remain future work. No guest global variables exist.

Capture lowering separates dense local frame slots from capture indices:
- NoCaptures: no parent frame/capture array is retained.
- ReuseCaptures: inner methods referencing only inherited captures share the
  exact array and keep its original indices, including subsets/reordering.
- CaptureValues: mixed/local captures use a flat snapshot array. Static
  source-index metadata is stored once in IR, not copied as pairs per closure.

Shared arrays retain their union, not just a child's subset. This is an
intentional trade-off. They never retain the outer method's local frame.
Recursive placeholders and boxes are shared by reference, not deep-copied.

Lowerer.lower ~optimize:false remains executable for differential tests.

## Timings

Seconds; each row compares the same workload and unit count.

| Workload | Units | v0.2 | Selectors/captures | Shared layouts | Pure-hook prototype |
| --- | ---: | ---: | ---: | ---: | ---: |
| Zero-capture creation | 100,000 | 0.167909 | 0.140977 | 0.098655 | 0.148652 |
| Inherited-capture creation | 100,000 | 0.237622 | 0.181035 | 0.095073 | 0.185640 |
| Custom decorating-hook loop | 100,000 | 0.945127 | 0.666821 | 0.526940 | 0.675913 |
| Tail loop | 1,000,000 | 3.797618 | 2.696424 | 1.367459 | 2.717857 |
| Sequence materialization | 100,000 | 0.700266 | 0.489559 | 0.286017 | 0.573302 |
| Encode bytes | 10,000 | 0.027483 | 0.018667 | 0.003338 | 0.018129 |

Production's combined changes reduce the measured million-loop time by about
29% and cumulative allocation from 14.232 GB to 9.656 GB (32% less).
This does not isolate selector interning from capture and registration changes.

The custom-hook workload wraps each number with an extra guest method. It
does not use the default identity hook, and it still benefits from production
changes and the layout prototype.

The shared-layout prototype reduces this loop's time further, but is not a
general shape engine and has separate representation/concurrency caveats.
The pure-hook prototype is not a broad win: the 100,000-entry sequence sample
was approximately 17% slower than production despite identical allocation.
Fixed-order, small-sample timings cannot establish the cause; repeat before
making a merge decision.

See the CSV files for exact allocated-byte totals and smaller sizes.
Allocation is cumulative, not live memory or peak RSS.

## Pure-hook-specific microbenchmark

100,000 number constructors under each custom hook; times in seconds.

| Hook | Production | Pure-hook prototype | Production bytes | Prototype bytes |
| --- | ---: | ---: | ---: | ---: |
| Direct identity | 0.117475 | 0.102792 | 373600096 | 365600096 |
| Direct captured constant | 0.105756 | 0.101616 | 370400096 | 361600096 |
| Fresh decoration (fallback) | 0.168926 | 0.163789 | 490400096 | 490400096 |

Only direct captured-variable returns have cached results. Identity hooks use
argument projection without caching an earlier argument's result.
Fresh object construction, calls, mutation and mutable reads are not proved
pure and retain normal execution. The fallback time difference is not credited
to caching: it has identical allocation and no cache fast path.

This is a narrow feasibility prototype. General purity alone does not prove
that sharing a previously fresh result is legal. Broader caching needs an
effect/call-target and aliasing/freshness model, not a history-based heuristic.

## Shared-layout semantics

The prototype shares immutable numeric selector/code arrays and carries a
numeric lexical payload separately. It does not obtain a method's number
from the destination object's tag. For example:

    A 1
    B {A (core tag 99)}
    B + 1

must still return 2. Inclusion creates bound entries preserving origin payloads.
The ordinary embedding get_method API still returns a bound callable;
interpreter dispatch can invoke the descriptor directly.

Generic objects remain tables. Custom numeric inclusion materializes entries.
Numeric code layout initialization uses Lazy.force and is not a validated
cross-domain initialization protocol. Neither prototype should be merged
without additional application and cross-platform testing.

## Methodology and reproduction

Host: OCaml 5.3.0 native, Dune 3.24.0, Cygwin on Windows.
Native Windows and Linux were not measured.

General harness: warm once, then median of three timed runs, full major GC
before each sample. Parsing/lowering and builds excluded. GC allocation is
recorded before the post-run GC. Runs were sequential, not concurrent.
The pure-hook harness uses five samples. Timings are local measurements,
without confidence intervals or randomized/interleaved branch order.

    dune build @install
    dune runtest --force
    dune exec test/benchmark.exe
    dune exec test/benchmark_pure.exe

The last command is present on production and the pure-hook branch.
For reference-commit comparisons, use the same harness from the production
branch rather than the older smaller harness at the reference commit.

The native runtime reports zero for Gc.stat.stack_size, so it is not used as
a physical stack measurement. Million-loop completion and compiler-checked
tail calls support stack safety, not bounded total memory.

## Conformance evidence

All three implementations passed the full existing suite: 52 v0.2 checks,
199 v0.1 checks, 96 environment/diagnostic checks, 50 stdlib checks,
173 calculator checks, all 50 examples and frontend/evaluator/CLI tests.

Production also checks selectors across threads, exact arities, capture plans,
shadowing, nested recursion, mixed captures, mutable boxes, and weak-reference
release of unrelated parent locals. Nine reference-evaluator comparisons
cover the same semantic cases. The two prototypes each add eight focused checks
for layout origin/overrides or purity-cache safety.

## Shared-storage follow-up

The separate [bounded-overlay report](SHARED_LAYOUT_OVERLAYS.md) measures the
refined prototype against the exact production and layout revisions above.
It includes identical real-stdlib/calculator workloads, reverse run ordering,
retained-heap samples, remaining generic-object regressions and raw CSVs.
The historical Lazy.force and materialized-inclusion limitations described
above apply to the original prototype, not that follow-up revision.

## Next decisions

Keep selectors and capture sharing in production.
Keep layouts and purity caching separate. The layout prototype is promising
enough for wider workloads, especially realistic custom environments.
The narrow purity proof is safe in covered cases but does not yet justify a
general caching claim or a default merge.
