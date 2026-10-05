# Style Guide

1. Limit lines to 80 columns. Exceed the limit only when wrapping would make the
  code materially less readable.
2. Indent in two-space increments. Use additional indentation where useful to
  make nested syntactic structure visually distinct. For example, a multiline
  `match` branch body may be indented two levels from the branch marker.
3. Use vertical alignment for small, coherent groups when it makes their shared
  structure easier to scan. Align corresponding parts of adjacent lines when the
  lines clearly belong together, but do not maintain alignment across unrelated
  code or large regions.
  ```ocaml
  let first  = record.first in
  let second = record.second in
  ```
4. Keep short expressions on one line. Do not introduce line breaks merely
  because an expression contains `let`, `if`, sequencing, or another construct
  that can remain clear and comfortably fit on one line.
5. Prefer meaningful `let` bindings over awkward wrapping. Records, tuples,
  function applications, and similar expressions should preferably remain on one
  line when concise. When they become difficult to wrap clearly, extract
  meaningful intermediate values. Wrap the expression directly when introducing
  names would only add noise.
6. When a delimited construct becomes multiline, make the delimiters visually
  balanced. Put its contents on separate indented lines and its closing
  delimiter on its own line.
  ```ocaml
  {
    first  = very_long_expression.
    second = another_long_expression.
  }
  ```
  Keep genuinely short constructs compact:
  ```ocaml
  { first. second }
  ```
7. Place binary operators at the beginning of continuation lines. This makes
  both the continuation and the structure of the expression immediately visible.
  ```ocaml
  "hello" ^ " " ^ "world" ^ " "
  ^ "and" ^ " " ^ "everyone"
  ^ " " ^ "else"
  ```
8. Avoid unnecessary parentheses. Rely on OCaml's precedence and syntactic
  structure when they are unambiguous. Use parentheses when they clarify
  grouping rather than defensively surrounding expressions.
9. Prefer type annotations at natural type boundaries. When a type annotation is
  useful documentation, put it on a function argument, return type, or `let`
  binding rather than using internal syntax merely to guide inference.
  ```ocaml
  let make_token kind pos : Token.t = { kind; pos }
  ```
10. When a record needs only local type disambiguation, qualify a field rather
  than annotate the whole expression. Prefer:
  ```ocaml
  { Token.kind = kind; pos }
  ```
  over:
  ```ocaml
  ({ kind; pos } : Token.t)
  ```
11. Optimize formatting for local readability rather than mechanical uniformity.
  Similar code should generally look similar, but a formatting rule may be
  relaxed when following it would obscure the structure it is intended to
  reveal.
