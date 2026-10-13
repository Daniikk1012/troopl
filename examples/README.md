# Runnable Troopl examples

Run from the repository root:

```sh
dune exec troopl -- examples/example_01.tr
dune runtest
```

Each file is self-contained, prints one line, and returns its demonstrated
result. No shared prelude, external files, input, or extra native methods are
required. The test suite checks both the returned value and exact stdout.

Only numbers, minimal booleans (`then-else`), minimal strings (`size`/`at`),
and the existing environment capabilities are assumed. Names such as `List`
and `Boolean` below are explicitly defined in the examples, not global built-ins.

## Catalogue

| File | Demonstration | Printed result |
|---|---|---|
| [01](example_01.tr) | Hello world. | `Hello, Troopl!` |
| [02](example_02.tr) | Definitions and arithmetic. | `42` |
| [03](example_03.tr) | Chains associate left. | `9` |
| [04](example_04.tr) | Explicit grouping. | `7` |
| [05](example_05.tr) | Trailing minus denotes a negative literal. | `10-` |
| [06](example_06.tr) | Modulo versus remainder. | `1` |
| [07](example_07.tr) | Powers and rounding. | `35` |
| [08](example_08.tr) | Double quotes escape a quote. | `He said "hello"` |
| [09](example_09.tr) | Unicode scalar count, not byte count. | `2` |
| [10](example_10.tr) | Characters are numeric code points. | `66` |
| [11](example_11.tr) | Named object methods. | `Ada` |
| [12](example_12.tr) | Method parameters. | `42` |
| [13](example_13.tr) | Overloading by arity. | `29` |
| [14](example_14.tr) | Lexical capture. | `42` |
| [15](example_15.tr) | Object inclusion and overriding. | `10` |
| [16](example_16.tr) | Numeric object inclusion. | `130` |
| [17](example_17.tr) | Blocks expose run/0. | `42` |
| [18](example_18.tr) | Only the selected block executes. | `42` |
| [19](example_19.tr) | Recursive self reference. | `42` |
| [20](example_20.tr) | Recursive factorial. | `720` |
| [21](example_21.tr) | Tail-recursive accumulation. | `5050` |
| [22](example_22.tr) | Inner lexical definitions preserve outer bindings. | `10` |
| [23](example_23.tr) | Define boolean not in Troopl. | `1` |
| [24](example_24.tr) | Define boolean and/or in Troopl. | `1` |
| [25](example_25.tr) | Define xor without numeric boolean conversion. | `1` |
| [26](example_26.tr) | Define fluent then/else in Troopl. | `42` |
| [27](example_27.tr) | Concatenate strings using only size and at. | `Hello, Troopl!` |
| [28](example_28.tr) | Substring as a view. | `bcd` |
| [29](example_29.tr) | Reverse as a view. | `stressed` |
| [30](example_30.tr) | Compare strings through their minimal interface. | `1` |
| [31](example_31.tr) | Pairs as objects. | `42` |
| [32](example_32.tr) | Construct a minimal two-element list. | `42` |
| [33](example_33.tr) | A lazy indexed range. | `13` |
| [34](example_34.tr) | Lazy map using run/1. | `9` |
| [35](example_35.tr) | Fold using run/2. | `15` |
| [36](example_36.tr) | Concatenate minimal lists lazily. | `4` |
| [37](example_37.tr) | Linked lists need no built-in list factory. | `30` |
| [38](example_38.tr) | Explicit mutable state. | `42` |
| [39](example_39.tr) | Encapsulated counter. | `3` |
| [40](example_40.tr) | Array push supports chaining. | `23` |
| [41](example_41.tr) | Array set and pop. | `28` |
| [42](example_42.tr) | Materialize a list into an encapsulated array. | `20` |
| [43](example_43.tr) | Switch the dynamic environment. | `42` |
| [44](example_44.tr) | Bind methods to an environment. | `42` |
| [45](example_45.tr) | Lexical capture and dynamic environment are distinct. | `42` |
| [46](example_46.tr) | Decorate new numbers through core extend number. | `points` |
| [47](example_47.tr) | Add not through core extend boolean. | `0` |
| [48](example_48.tr) | Evaluate code in the current environment. | `42` |
| [49](example_49.tr) | Partial application through closures. | `42` |
| [50](example_50.tr) | Compose function objects. | `42` |

## What is implemented in Troopl?

Examples 23–26 build boolean conveniences, 27–30 implement string operations
through views and recursion, and 31–37 construct pairs and list abstractions.
Example 42 materializes a lazy list using an encapsulated array.
Examples 49–50 implement partial application and function composition.

These are demonstrations, not a complete collection library. The two-element
list in 32 and views in 27–29/33–36 assume valid indices; they do not add bounds
checking. Lazy map reevaluates its function on every access, unlike a strict map.

## Current runtime details

- Numeric negatives use a trailing minus, including printed numbers (`10-`).
- Calls chain left-to-right; parentheses control grouping.
- Booleans select values; select blocks and call `run` for lazy branches.
- Strings expose Unicode scalar values, not Java UTF-16 code units.
- `[]` runs to the current environment. Use `[{}]` to return an empty object.
- `box set` and `array push` return their receiver; `array set` returns the
  assigned element, and `array pop` returns the removed element.
- Extension hooks are `core extend number`, `core extend boolean`, etc.
- `eval` currently takes one source-string argument and uses the current
  environment. Example 48 supplies an environment through `env run`.
- No examples depend on unimplemented filesystem, import, native list factories,
  native boolean conveniences, native string conveniences, or `core from-seq`.

The catalogue follows the current implementation, not every proposed API in the
specification. In particular, it avoids `core tag` and IO success-status probing:
those paths are not needed to demonstrate the language's object model.

`expectations.tsv` records independently specified expected results and stdout;
`test/test_examples.ml` evaluates all 50 files with the real default environment.
