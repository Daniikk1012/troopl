# Stack-based concatenative language as a TrOOPL library

This is one of the examples showcasing how flexiblity of TrOOPL allows it to be
used in ways beyond just object-oriented programming.
This particular example focuses on defining facilities to make TrOOPL behave as
if it was a concatenative stack-based language similar to FORTH or Factor.

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
