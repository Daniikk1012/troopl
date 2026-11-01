# Consolidated review: runtime changes and measurements

Measured 2026-11-01. Addresses the required selector, IR, capture-interface
and formatting notes from review5725358816 on PR3. The review also applies
to the dependent capability branches and independent shared-layout prototype.

## Shared changes

- Builtins.extend accepts a selector directly. Fixed extension signatures,
  filesystem metadata/operation methods and result fields use precomputed IDs.
- IR Call stores its selector without a duplicate name. Selector.name supplies
  the original name when printing IR, including names containing slashes.
- Capture_lowering exposes only lower through its interface.
- Empty captures use CaptureValues [||]; nonempty inherited captures still
  reuse the parent's array. Empty plans never select inherited-array reuse.
- A direct gather loop handles all CaptureValues lengths without a mapper
  closure or a separate zero-capture variant.
- Runtime construction/dispatch code is within the 80-column style limit.

The language's hook ordering, original method bindings, recursive placeholders,
minimal interfaces and fatal-error behavior are preserved. A new weak-reference
test checks that an empty-capture child releases a nonempty inherited array,
in addition to the existing tests for releasing parent local frames.

## Measurement method

Before: fc4f132, the reviewed production head. After: 0bc2f8d, including the
shared review changes. The identical test/benchmark.ml harness runs from each
checkout. OCaml5.3.0 native, Dune3.24.0, Cygwin on Windows; other platforms
were not tested. Builds and parsing/lowering are excluded from timing.

Each workload warms once, then reports the median of three samples, with
major GC before sampling. The implementations run sequentially, first
before/after, then after/before. Raw CSVs are in review-runtime/. These are
local samples without confidence intervals, not a general speedup claim.

## Results

Seconds per batch, first / reverse order.

| Workload | Units | Before | After |
| --- | ---: | ---: | ---: |
| Zero-capture creation | 100,000 | .140870 / .139424 | .142848 / .142430 |
| Inherited-capture creation | 100,000 | .177392 / .177304 | .173475 / .172963 |
| Custom decorating-hook loop | 100,000 | .652872 / .652279 | .673206 / .670846 |
| Tail loop | 1,000,000 | 2.664008 / 2.661615 | 2.588542 / 2.574859 |
| Sequence materialization | 100,000 | .481024 / .481319 | .483937 / .487608 |
| Encode bytes | 10,000 | .018088 / .018057 | .017770 / .018093 |

Timings are mixed: the million loop is about3% faster, inherited-capture
creation about2-2.5% faster, zero-capture creation about1-2% slower, and the
custom-hook loop about3% slower. Sequence materialization is also slightly
slower. Do not characterize these cleanups as an interpreter-wide improvement.

Cumulative allocated bytes per batch (same values in both orders):

| Workload | Before | After |
| --- | ---: | ---: |
| Zero-capture creation,100k | 407200304 | 402400304 |
| Inherited-capture creation,100k | 600000304 | 595200304 |
| Custom-hook loop,100k | 1906414680 | 1896814536 |
| Tail loop,1M | 9656007944 | 9560007800 |
| Sequence materialization,100k | 1299194384 | 1294394288 |
| Encode bytes,10k | 45492152 | 45492152 |

Allocation decreases in the closure/loop samples, despite small timing
regressions in some workloads. Allocation totals are not retained heap or RSS.
The harness's live-word values include GC timing effects; the dedicated weak
tests are the evidence for releasing unrelated captured payloads. A zero GC
stack-size field is not a physical stack-space measurement.

## Validation and optional suggestions

The complete production suite passed:199 v0.1 checks,52 v0.2 checks,
96 environment/diagnostic checks,50 stdlib checks,173 calculator checks,
all50 examples, frontend/evaluator/CLI checks and33 optimization checks.
The same shared changes must be validated on each capability/layout variant.

The optional removal of string-based embedding conveniences is deferred;
dynamic names/arities still need explicit interning, and existing embedding
callers remain supported. Fixed-signature capability hot paths use IDs.
The optional Method/CompiledMethod unification is also deferred to preserve
the independent reference-lowering/evaluator path without a broader IR rewrite.
Neither optional suggestion is required by the review.

Reproduce:

    dune build @install
    dune runtest --force
    dune exec test/benchmark.exe

Review: https://github.com/Daniikk1012/troopl/pull/3#pullrequestreview-5725358816
