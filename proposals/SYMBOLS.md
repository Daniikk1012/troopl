# Opt-in private method keys

`symbol new` returns a key with `new-method Arity Source`,
`invoke Target Arguments` and `run Arity Target`.
The global compatibility methods are `symbol new-method K N B`,
`symbol run K N O` and `symbol equal? A B`.

Keys capture fresh selector families, separate from public string interning.
Including a key intentionally delegates its authority and preserves its brand.
Instances include private bindings, not the key itself. A factory can retain
one key to provide class-private access between its instances.
No global instance pool exists. Reverse-selector labels retain metadata only,
never instance data or key capabilities. Public text "<private>" cannot recover
a private selector. A private method alias retains its original captures and
environment binding; there is no implicit self.

Enabled only through `--experimental` / `Experimental.extend`.
This branch stacks on metaprogramming; neither proposal changes v0.2 defaults.
