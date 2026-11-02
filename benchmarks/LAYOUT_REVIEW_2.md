# Shared-layout review: representation and storage policy

Review: [Daniikk1012 on PR #9](https://github.com/Daniikk1012/troopl/pull/9#issuecomment-6566479990).
Measured on 2026-11-02. This follow-up targets the layout prototype, not the
independent meta/private-key/control branches.

## Numeric storage and eager initialization

`Numeric` now stores only the original `float`. `Value` owns one sorted table
of shared numeric method bodies, initialized eagerly when the module loads.
There is no numeric-layout pointer per object, lazy cache, atomic read, mutex,
registration API, or guest-value cache. The former arbitrary numeric-layout
prototype API was used only by tests; it has been removed.

Static recursive values tie the callable table to primitive constructors;
its entries are closures, so constructing the table does not run their bodies.
The private array is sorted once before module initialization completes and
never mutated afterward. OCaml explicitly supports this kind of
[statically constructive recursive value](https://ocaml.org/manual/5.3/letrecvalues.html).

Primitive construction lives with dispatch to avoid a Value/Builtins dependency
cycle. `Builtins` retains its public constructor API as aliases, and
`Number_format` contains the representation-formatting helpers. The lookup
wrapper captures only the selected shared body and its original numeric value.
No guest code or extension hook runs while the table is initialized.

Every numeric, boolean, and string result still passes through its active
environment's extension hook. Strings construct character numbers from left
to right, then their length, then call the string hook. Numbers are not cached.
The captured numeric value remains independent of the containing object's tag:
including a number's methods and subsequently replacing the tag must not change
those methods' original captured value. Binding preserves the bound environment.

This implements the representation simplifications asked in questions 1 and 4.
The reviewer's `Array.map` change is included unchanged. The comparison baseline
also includes it, so these measurements do not compare array-gather strategies.

## Duplicate selector enumeration

`iter_selectors` is private and intentionally enumerates shadowed entries too.
Its only two consumers deduplicate: flattening resolves each selector once,
and diagnostic printing builds a selector set. Neither enumeration nor
flattening invokes a guest method or a binding callback.

A regression covers repeated inclusions, overridden selectors, diagnostic
uniqueness, and callbacks before/after flattening. Both existing consumers are
safe. Any future consumer must obey the documented duplicate contract; making
this iterator public without specifying that contract would be inappropriate.

## One-level flattening experiment

The existing policy materializes the effective method set whenever storage
depth exceeds eight. The experimental policy instead reduces every deepest
path by one level: it materializes depth-two subtrees and rebuilds ancestors.
For branching merges, all deepest children must be reduced to actually lower
the maximum depth. A single local rewrite cannot always do that.

The candidate is reproducible using `prepare_partial_flatten.py`; it is not a
runtime option. Both policies must preserve last-definition precedence,
original numeric captures, bound environments, callback order, and collection
of overwritten closures. The experiment also measures actual stdlib and
calculator execution, not just artificial method-map lookups.

## HAMT assessment

A persistent trie is compatible with TrOOPL. A map keyed by selector IDs would
naturally hold each effective selector once; replacement path-copying could
remove overridden closures without a depth-triggered flattening policy. It
could replace Table/Shared/Overlay/Merge with fewer representation cases.
There is no semantic blocker requiring an implicit receiver.

It would not eliminate these costs or requirements:

- A numeric entry must preserve its original captured value. Converting every
  number into a trie of allocated callable closures would lose the current
  compact numeric representation; keep Numeric as a specialized leaf or store
  numeric descriptors with their lexical payload.
- Binding still needs its captured environment and callback ordering. Either
  retain a bound wrapper or map over the entries. The latter costs construction
  work proportional to the number of methods.
- Inclusion needs a right-biased structural union, not merely fast lookup.
  Folding inserts is a correctness baseline, but may allocate considerably
  more than sharing an existing method set.
- Most native objects are small. Bitmap nodes, path copying and extra
  indirections may outweigh sharing benefits. Sequential integer selectors
  also warrant testing direct integer tries against hashed keys.

The [CHAMP paper](https://michael.steindorfer.name/publications/oopsla15.pdf)
shows that node layout, locality and iteration costs materially affect HAMT
performance. Its JVM results do not establish an OCaml speedup. The
[OCaml HAMT API](https://ocaml.org/p/hamt/1.0.0/doc/hamt/Hamt/index.html)
demonstrates an available persistent-map implementation, not evidence of
suitability for this interpreter's union and binding workload.

Recommendation: benchmark a separate integer-trie/HAMT backend with compact
numeric leaves and explicit right-biased union, against tiny/native objects,
wide guest objects, repeated overriding, bindings and the calculator. Measure
allocation and live heap as well as dispatch time. Do not replace the current
backend based only on asymptotic lookup complexity. This review requested an
assessment before implementing HAMTs; no unmeasured HAMT runtime is introduced.

## Final measurements

Baseline: `8f6b859` (PR #14 plus the reviewer's `Array.map` change).
Final implementation: `8cdfdf0`. The partial candidate is generated from that
exact final commit with `prepare_partial_flatten.py`; only its flattening policy
and the archived example-manifest line endings differ.

OCaml 5.3.0 native, Dune 3.24.0 bootstrap executable, Cygwin on Windows.
Warm once, median of five batches after major GC; sequential baseline/full/
partial, then partial/full/baseline. No builds or installer ran during timing.
Parsing, source loading and setup are excluded. No confidence intervals or
cross-platform validation; small timings are sensitive to host variability.
All CSVs directly in [layout-review-2/](layout-review-2/) are final samples.

### Numeric/runtime comparison

Seconds per batch, first / reverse run order. Allocation is bytes per unit.

| Workload | Units | Before seconds | After seconds | Before bytes | After bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| construct-native | 20000 | 0.001432 / 0.001506 | 0.001333 / 0.001287 | 352.01 | 104.01 |
| construct-stdlib | 20000 | 0.019230 / 0.019186 | 0.021654 / 0.020960 | 2072.01 | 1824.01 |
| construct-two-inclusions | 20000 | 0.017237 / 0.019042 | 0.019639 / 0.017158 | 2928.01 | 2680.01 |
| include-existing-number | 50000 | 0.001802 / 0.002012 | 0.002140 / 0.001972 | 296.00 | 296.00 |
| construct-eight-guest-methods | 50000 | 0.013216 / 0.014457 | 0.014973 / 0.013366 | 1168.00 | 1168.00 |
| embedding-numeric-lookup | 1000000 | 0.012105 / 0.013202 | 0.014686 / 0.014242 | 48.00 | 48.00 |
| bind-existing-number | 20000 | 0.000181 / 0.000197 | 0.000203 / 0.000203 | 72.01 | 72.01 |
| calculator-with-stdlib | 1000 | 1.472312 / 1.529012 | 1.534715 / 1.533280 | 2769719.67 | 2582047.42 |

Native construction allocates about 70.5% less, stdlib numeric construction
about 12.0% less, and the calculator about 6.8% less. These savings include
centralizing primitive construction/extension dispatch; they are not all
attributable to removing one pointer. Every required hook still runs.

Timing is a tradeoff. Native construction is about 7–15% faster in these
samples, but stdlib construction is about 9–13% slower and extracted numeric
method lookup about 8–21% slower. Calculator time is about 0.3–4.2% slower.
Other small samples change direction with run order. No general throughput
improvement is claimed. The evaluator uses direct `invoke_id`; the extracted
method benchmark measures the separate embedding `get_method_id` path.

### Retained heap

After full major GC, holding 10,000 results. Bytes per output include its array
slot; already-rooted source values and fixed startup tables are excluded.

| Workload | Before bytes | After bytes |
| --- | ---: | ---: |
| native-number | 96.00 | 88.00 |
| stdlib-number | 752.00 | 744.00 |
| include-existing-number | 73.75 | 73.75 |
| bind-existing-number | 80.00 | 80.00 |

Numbers and stdlib-extended numbers retain eight fewer bytes per output.
These are live-heap measurements, not RSS. Shallow inclusion/binding results
are unchanged. Separate weak-reference regressions verify collection of
overwritten closures and unrelated lexical captures.

### Full versus one-level flattening

Same final callable representation. Seconds per batch, first / reverse order.

| Workload | Units | Full seconds | Partial seconds | Full bytes/unit | Partial bytes/unit |
| --- | ---: | ---: | ---: | ---: | ---: |
| override-8 | 2000 | 0.000970 / 0.000976 | 0.003397 / 0.003465 | 548.30 | 1917.52 |
| lookup-8 | 100000 | 0.002591 / 0.002452 | 0.008051 / 0.008062 | 0.00 | 0.00 |
| override-64 | 2000 | 0.005849 / 0.005055 | 0.022453 / 0.022876 | 1153.51 | 6742.27 |
| lookup-64 | 100000 | 0.003174 / 0.002874 | 0.010910 / 0.010642 | 0.00 | 0.00 |
| override-512 | 2000 | 0.041691 / 0.038772 | 0.181016 / 0.187129 | 6624.43 | 50356.75 |
| lookup-512 | 100000 | 0.003102 / 0.002943 | 0.010711 / 0.011554 | 0.00 | 0.00 |
| bind-chain | 2000 | 0.000054 / 0.000052 | 0.000387 / 0.000387 | 109.86 | 653.68 |

The one-level policy repeatedly copies the bottom table and rebuilds ancestors,
while keeping longer lookup paths. Override allocation grows by about 3.5×
(8 selectors), 5.8× (64), and 7.6× (512). Both policies pass conformance and
retention tests, so this is a performance decision, not a semantic rejection.

The calculator runs mostly below the depth threshold. Full versus partial
calculator timings are 1.534715 / 1.533280 versus 1.470433 / 1.526326 seconds,
with identical allocation. Those samples do not outweigh the repeatable
override/lookup cost. **Retain full flattening.** This rejects the measured
deepest-subtree policy; it does not prove every possible incremental policy
would be slower.

## Validation and reproduction

Both final policies passed `dune build @install` and the full suite: 199 v0.1,
52 v0.2, 96 environment/diagnostic, 50 stdlib, 173 calculator, all 50 examples,
CLI/frontend/evaluator checks, 33 optimization, 220 storage, 8 numeric-layout
and 14 new review checks. Four-domain tests preserve all 40,000 custom hooks.

Export `8f6b859` for the baseline and `8cdfdf0` for the final full policy.
Copy `test/benchmark_storage.ml` and its executable/exclusion stanza from the
final revision into the baseline (benchmark harness only). The existing
`benchmark_layout.ml` is unchanged. Normalize `examples/expectations.tsv` to
LF in exports, matching the working checkout; committed CRLF otherwise causes
a fixture-only failure in the example harness.

From the repository root, prepare a separate partial candidate:

```sh
python benchmarks/prepare_partial_flatten.py 8cdfdf0 NEW_DIRECTORY
```

Build and test each exported tree. From each root, run:

```sh
dune build @install test/benchmark_layout.exe test/benchmark_storage.exe
dune runtest --force
_build/default/test/benchmark_layout.exe
_build/default/test/benchmark_layout.exe --retained
_build/default/test/benchmark_storage.exe
```

Repeat in reverse order with no concurrent compiler or benchmark processes.
Edited sources use ocamlformat 0.29.0 default formatting. Native installation
hit a Dune/Cygwin build error; formatting was performed offline using its
JavaScript build, with separate signature parsing and idempotence checks.

Intermediate evidence is retained separately: `intermediate/` measures the
initial descriptor implementation (`31b770b`, partial generated at `4a17107`);
`intermediate-search/` measures `a209af2` after removing its search closure.
The final shared-callable table eliminates the remaining descriptor-wrapper
capture. Do not use those intermediate files as final results.
