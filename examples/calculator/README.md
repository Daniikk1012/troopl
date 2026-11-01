# Troopl calculator

An interactive calculator written in Troopl. It parses arithmetic itself;
user expressions are never passed to the interpreter's `eval` capability.

## Run

From the repository root:

```sh
dune build
dune exec troopl -- examples/calculator/main.tr
```

The launcher loads the English stdlib and calculator module, then starts a
read/evaluate/print loop. `:quit` or EOF exits normally. It does not create
files unless you explicitly use `:save`.

Example session:

```text
calc> 2 + 3 * 4
14
calc> (2 + 3) * 4
20
calc> radius = 5
5
calc> pi * radius ^ 2
78.539816339744831
calc> sqrt(81) + max(2, 3)
12
calc> -2^2
-4
calc> 1 / 0
Error at column 6: division by zero
calc> ans
-4
calc> :quit
```

Errors are printed to stderr; the prompt and results use stdout.

## Expressions

- Decimal numbers starting with a digit, such as `42`, `0.5`, and `12.25`.
- Operators `+`, `-`, `*`, `/`, `%`, and `^`.
- Unary `+` and `-`, parentheses, and whitespace.
- Variables assigned with `name = expression`.
- Constants `pi`, `e`, and `ans` (the last successful result, initially zero).
- Functions `abs`, `sqrt`, `floor`, `ceil`, `trunc`, `min`, `max`, and `pow`.

Function arguments are comma-separated: `pow(2, 10)` and `min(4, 7)`.
Names are case-sensitive ASCII letters/underscores followed by
letters/underscores/digits. Constants cannot be reassigned.

Power is right-associative: `2^3^2` means `2^(3^2)`. Power binds more tightly
than a unary sign: `-2^2` is `-4`, and `(-2)^2` is `4`. Negative exponents work:
`2^-3` is `0.125`. Other binary operators are left-associative, with ordinary
multiplication-before-addition precedence. `%` is Euclidean modulo.

This input language uses conventional leading minus signs, not Troopl's
negative-literal suffix. Results are also formatted with leading minus signs.
Numbers use the interpreter's floating-point representation and decimal
formatting; this is not an arbitrary-precision financial calculator.
Scientific notation, implicit multiplication, and user-defined functions are
not supported.

Bad expressions return error objects with a message and column. They do not
change variables, `ans`, or history. Division/modulo by zero and negative
square roots are reported without terminating the session.

## Commands

| Command | Action |
|---|---|
| `:help` | Show syntax and commands |
| `:vars` | List assigned variables |
| `:history` | Show successful expressions and assignments |
| `:clear` | Clear variables/history and reset `ans` |
| `:save PATH` | Write history to a UTF-8 file, replacing existing contents |
| `:load PATH` | Replay expressions from a file |
| `:info PATH` | Show existence/type, byte size, and modification timestamp |
| `:files PATH` | List a directory's entry names |
| `:pwd` | Show the current working directory |
| `:time` | Show the Unix timestamp |
| `:exec PROGRAM` | Explicitly run one executable and display its output/status |
| `:quit` | Exit normally |

Paths may contain spaces; everything after the command is treated as the
path. Do not add shell quotes. Paths are relative to the process working
directory, not the imported module's directory.

`:exec` runs exactly one executable with no arguments and empty stdin. It
does not use a shell or expand metacharacters. Supply an executable path or
name discoverable on `PATH`; this command is intentionally explicit access
to the environment's process capability. Merely typing an arithmetic
expression cannot execute a process. The runtime captures stdout/stderr
separately, and nonzero exit codes are reported rather than crashing.

## Saved sessions

A session file contains one successful expression or assignment per line.
Blank lines are ignored when loading. No Troopl source or calculator commands
are executed by the loader.

Loading replays into the current session. Use `:clear` first to reconstruct
the original session from its initial state. Replay stops at the first bad
line and reports its line number; earlier successful lines remain applied.
Successful replayed expressions also enter history. History records inputs,
so files remain human-readable and editable.

The calculator does not automatically load or overwrite files on startup.

## Code and language features

`main.tr` provides the launcher and command loop. `calculator.tr` exports a
factory with `new`, producing independent session objects. A session exposes
`calculate`, `variables`, `history`, `previous`, `clear`, `save`, and `load`.

The parser is a recursive object with captured input, boxes for its position
and first error, and methods for primary expressions, powers, unary signs,
products, and sums. Operator chains use tail-recursive accumulator methods.
Variable bindings and history use native arrays, exposed as strict stdlib list
snapshots. Control flow uses Church booleans and stdlib conditionals.

Dynamic environments supply IO, filesystem access, time/process capabilities,
and builtin extensions. There are no global builtin variables and no
calculator-specific native methods. Module loading uses the existing stdlib
import mechanism. The launcher runs trusted Troopl module code, while the
calculator itself treats interactive input strictly as data.

## Tests

```sh
dune runtest
```

Tests cover precedence, associativity, functions, variables, constants, error
recovery, long additive chains, session replay, and the actual CLI with
scripted stdin. Version 0.1 runtime tests separately exercise lossless bytes,
filesystem operations, flushing, and binary/large subprocess output.
