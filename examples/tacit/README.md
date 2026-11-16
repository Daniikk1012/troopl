# Combinator library for tacit (point-free) programming in TrOOPL

This is one of the examples showcasing how flexiblity of TrOOPL allows it to be
used in ways beyond just object-oriented programming.
This particular example focuses on defining a bunch of combinators to make
tacit-free programming easy in TrOOPL.

To run the example, switch to this directory:

```sh
cd examples/tacit
```

... and then run:

```sh
dune exec troopl init.tr
```

`init.tr` is the launcher, `lib.tr` contains the definition of the environment,
`main.tr` contains example code that uses that environment.
