# Shared-layout review: representation and storage policy

Review: [Daniikk1012 on PR #9](https://github.com/Daniikk1012/troopl/pull/9#issuecomment-6566479990).
Measured on 2026-11-02. This follow-up targets the layout prototype, not the
independent meta/private-key/control branches.

## Numeric storage and eager initialization

`Numeric` now stores only the original `float`. `Number_methods` owns one
sorted operation table, constructed eagerly during module initialization.
There is no numeric-layout pointer per object, lazy cache, atomic read, mutex,
registration API, or guest-value cache. The former arbitrary numeric-layout
prototype API was used only by tests; it has been removed.

The descriptor table contains pure arithmetic/comparison operations and a
conversion marker. `Value` applies these descriptors and constructs primitive
results. `Builtins` retains its public constructor API as aliases. Keeping
primitive construction with dispatch breaks the former Value/Builtins cycle
without recursive modules or runtime initialization callbacks. No guest code
runs while the shared table is built.

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
