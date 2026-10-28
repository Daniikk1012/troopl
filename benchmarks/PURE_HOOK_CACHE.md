# Pure-hook cache feasibility prototype

Branch: codex/prototype-pure-hook-cache, independent of shared layouts.

This branch proves only two syntactic cases for guest number/boolean/string/list
extension methods:
- A direct captured-variable return always returns the same captured reference.
  Resolve it once when constructing the closure and cache that result.
- A direct argument return is identity/projection. Specialize the dispatch;
  never memoize one argument's result for a different argument.

There is no user purity annotation and no speculative inference from history.
Dynamic calls, object construction, mutable reads and sequences are Unknown
and use the ordinary evaluator. Accessors core/extend are not cached.
This is not numeric-value memoization and not a general pure-function cache.

Why the boundary matters: even an effect-free decorator may return a fresh
object or capture the current input. Proving absence of IO alone is not enough
to authorize reusing a previous result. General support needs an effect,
aliasing/freshness and dynamic-call analysis or a specified stronger contract.

The cached constant is an existing captured reference. Mutable objects behind
that reference stay mutable; their contents are not snapshotted. Invoking a
method such as box get is not classified as a constant return. Recursively
captured placeholders retain their reference and normal initialization checks.

Full existing conformance suite and eight dedicated safety checks pass.
The focused tests cover distinct decorator results, side effects, box reads,
identity and constant hooks, and rejection of non-hook methods.

Run:
    dune exec test/benchmark_pure.exe
    dune exec test/benchmark.exe

Results and comparison are recorded in benchmarks/RESULTS.md on the production
branch. The narrow case does not optimize the common fresh-decorator hook;
do not merge based on the default loop or identity-hook microbenchmark alone.
