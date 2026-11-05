# Shared-layout consolidated review follow-up

Measured2026-11-01. Compares original PR9 head3d43db3 with reviewed source
c403c87. Both use the same test/benchmark_layout.ml harness. Shared review
changes and production measurements are in [REVIEW_FIXES.md](REVIEW_FIXES.md).

The review preserves shared numeric code/payloads, bounded inclusion/binding
storage and atomic publication. Builtin hooks use selector arguments; Call
no longer stores a duplicate name; CaptureValues[||] replaces NoCaptures.
Empty gathers return the empty array directly, as in OCaml's array routines.

An intermediate generic gather loop made the two-inclusion workload14-19%
slower. Empty-input handling recovered that sample without reintroducing the
redundant IR variant. Only the complete corrected matrix is tabulated here.

## Method

OCaml5.3.0 native, Dune3.24.0, Cygwin on Windows. Build/parsing/loading and
calculator source-string construction are excluded. Warm once, median5 after
major GC, first old/new then new/old. Implementations do not run concurrently.
There are no confidence intervals; timings are local observations. Raw files
are in review-layouts/. Other platforms were not tested.

## Final timings

Seconds per batch, first / reverse order.

| Workload | Units | Before | After |
| --- | ---: | ---: | ---: |
| Native number | 20,000 | .001634 / .001696 | .001615 / .001573 |
| Actual stdlib number | 20,000 | .019867 / .022160 | .019514 / .019628 |
| Two inclusion layers | 20,000 | .017183 / .018681 | .017006 / .017206 |
| Include existing number | 50,000 | .001858 / .002008 | .001813 / .001841 |
| Eight guest methods | 50,000 | .013501 / .014588 | .012977 / .013069 |
| Embedding numeric lookup | 1,000,000 | .011958 / .014225 | .012271 / .012351 |
| Bind existing number | 20,000 | .000179 / .000192 | .000185 / .000183 |
| Stdlib calculator | 1,000 | 1.443443 / 1.633473 | 1.550586 / 1.476720 |

Calculator timing changes direction with run order: about7% slower in one
batch and about10% faster in the other. Do not claim a stable calculator
speedup from these samples. Short embedding/binding timings are also mixed.
The layered-hook regression from the intermediate gather is absent in the
corrected matrix, but these comparisons do not establish universal gains.

## Allocation and retained heap

Cumulative allocation per stdlib number falls from2072 to1928 bytes, about7%.
Calculator allocation falls from2761847.67 to2532599.10 bytes per expression,
about8.3%. Other measured allocation/unit values are unchanged: native352,
two inclusions2784, existing inclusion296, eight methods1168, lookup48,
binding72 bytes (rounded). Both run orders agree on these allocation values.

The separate10,000-output retained-array measurement includes its eight-byte
slot per object. It excludes already-rooted source objects/layout metadata.

| Retained object | Before bytes/output | After bytes/output |
| --- | ---: | ---: |
| Native number | 96.00 | 96.00 |
| Stdlib number | 752.00 | 752.00 |
| Existing-number inclusion | 73.07 | 73.75 |
| Existing-number binding | 80.00 | 80.00 |

No broad retained-heap improvement is claimed. Allocation totals are not RSS;
small retained-size differences include shared overhead. Dedicated weak-ref
tests establish release of overwritten and unrelated captured payloads.

## Validation

After the final gather correction, the full suite passes:199 v0.1,52 v0.2,
96 environment/diagnostic,50 stdlib,173 calculator,all50 examples, CLI/frontend
checks and33 optimization checks. Layout-specific coverage passes220 storage
checks,8 original layout checks and four concurrent first-use domains with all
40,000 custom-hook calls preserved. Native selector types remain specialized
integers and runtime lib/bin source stays within80 columns.

The optional capability stack is not merged into this prototype. Shared
review fixes are carried in a dedicated follow-up; original PRs are unmerged.

    dune build @install
    dune runtest --force
    dune exec test/benchmark_layout.exe
    dune exec test/benchmark_layout.exe -- --retained
