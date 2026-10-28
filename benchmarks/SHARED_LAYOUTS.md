# Shared numeric layouts prototype

Branch: codex/prototype-shared-layouts. Not merged into the production branch.

Fresh numeric objects share an immutable sorted selector-to-code array.
Each object carries its numeric capture separately. Copying methods into an
ordinary object creates bound entries retaining that original capture, even
when a later inclusion changes the destination object's numeric tag.
Guest method signatures and arities are unchanged: no implicit self.

The interpreter dispatches shared entries without allocating a bound OCaml
closure per call. The embedding get_method API still produces a bound callable.
Generic objects remain hash tables; this is not a general shapes implementation.
All extension hooks still run. Native layout initialization uses Lazy.force;
cross-domain initialization remains a limitation of this experimental path.

Full conformance suite passes, plus focused inclusion/override/payload tests.
Build and benchmark on Cygwin, OCaml 5.3.0, Dune 3.24.0. Native Windows/Linux
not tested. See benchmarks/RESULTS.md on the production branch for the matrix.

The layouts reduce native allocations, but extending numbers via object
inclusion materializes bound entries again. Do not extrapolate default-core
benchmark gains to every custom extension. A broader shared-layout design
needs profiling for heterogeneous methods, sparse overrides and env bind.
