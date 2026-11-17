"""Checks both generated grammars against the interpreter's own lexer.

Usage: python editors/check.py [path/to/troopl] [files...]

Without files it checks every .tr file in the repository. Each grammar is run
by a small, dependency-free TextMate / Sublime engine (Python re, with
\\p{Lu}/\\p{Lt} expanded from unicodedata). Every token reported by
`troopl --tokens` must start with a scope of the right class, every comment
character must be a comment, and the context cases below must hold.
"""

import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def letter_class():
    ranges, start, previous = [], None, None
    for code in range(sys.maxunicode + 1):
        if 0xD800 <= code <= 0xDFFF:
            continue
        if unicodedata.category(chr(code)) in ("Lu", "Lt"):
            if start is None:
                start = code
            elif code != previous + 1:
                ranges.append((start, previous))
                start = code
            previous = code
    ranges.append((start, previous))
    return "".join(
        re.escape(chr(a)) + ("-" + re.escape(chr(b)) if b != a else "")
        for a, b in ranges
    )


UPPER = letter_class()


def compile_(pattern, variables=None):
    if variables:
        for _ in range(4):
            pattern = re.sub(
                r"\{\{(\w+)\}\}", lambda m: variables[m.group(1)], pattern
            )
    anchored_g = pattern.startswith("\\G")
    anchored_a = pattern.startswith("\\A")
    if anchored_g or anchored_a:
        pattern = pattern[2:]
    pattern = pattern.replace(r"\p{Lu}\p{Lt}", UPPER)
    return re.compile(pattern), anchored_g, anchored_a


class Matcher:
    def __init__(self, pattern, variables=None):
        self.regex, self.g, self.a = compile_(pattern, variables)

    def search(self, line, pos, anchor, first_line):
        if self.g:
            return self.regex.match(line, pos) if pos == anchor else None
        if self.a:
            return self.regex.match(line, pos) if first_line and pos == 0 else None
        return self.regex.search(line, pos)


def paint(scopes, start, end, names):
    for i in range(start, end):
        scopes[i] = names


class TextMate:
    def __init__(self, grammar):
        self.grammar = grammar
        self.cache = {}

    def rules(self, owner):
        key = id(owner)
        if key not in self.cache:
            out = []
            for rule in owner.get("patterns", []):
                if "include" in rule:
                    target = self.grammar["repository"][rule["include"][1:]]
                    out.extend(self.rules(target) if "patterns" in target
                               and "begin" not in target and "match" not in target
                               else [self.prepare(target)])
                else:
                    out.append(self.prepare(rule))
            self.cache[key] = out
        return self.cache[key]

    def prepare(self, rule):
        if "_m" not in rule:
            rule["_m"] = Matcher(rule.get("match") or rule["begin"])
            if "end" in rule:
                rule["_e"] = Matcher(rule["end"])
        return rule

    def captures(self, scopes, match, base, captures):
        for group, value in (captures or {}).items():
            group = int(group)
            if match.group(group) is not None and match.start(group) < match.end(group):
                paint(scopes, match.start(group), match.end(group),
                      base + [value["name"]])

    def tokenize(self, text):
        stack = [(self.grammar, [], -1)]
        result = []
        for number, line in enumerate(text.split("\n")):
            line += "\n"
            scopes = [None] * len(line)
            stack = [(rule, names, -1) for rule, names, _ in stack]
            pos = 0
            while pos < len(line):
                rule, names, anchor = stack[-1]
                best = None
                if "_e" in rule:
                    m = rule["_e"].search(line, pos, anchor, number == 0)
                    if m:
                        best = (m.start(), 0, None, m)
                for order, child in enumerate(self.rules(rule), 1):
                    m = child["_m"].search(line, pos, anchor, number == 0)
                    if m and (best is None or (m.start(), order) < best[:2]):
                        best = (m.start(), order, child, m)
                if best is None:
                    paint(scopes, pos, len(line), names)
                    break
                start, _, child, m = best
                paint(scopes, pos, start, names)
                if child is None:
                    paint(scopes, start, m.end(), names)
                    self.captures(scopes, m, names, rule.get("endCaptures"))
                    stack.pop()
                elif "match" in child:
                    inner = names + ([child["name"]] if "name" in child else [])
                    paint(scopes, start, m.end(), inner)
                    self.captures(scopes, m, inner, child.get("captures"))
                else:
                    inner = names + ([child["name"]] if "name" in child else [])
                    paint(scopes, start, m.end(), inner)
                    self.captures(scopes, m, inner, child.get("beginCaptures"))
                    stack.append((child, inner, m.end()))
                if m.end() == pos and child is not None and "match" in child:
                    paint(scopes, pos, pos + 1, names)
                    pos += 1
                else:
                    pos = m.end()
            result.append(scopes)
        return result


class Sublime:
    def __init__(self, path):
        self.syntax = parse_yaml(path.read_text(encoding="utf-8"))
        self.variables = self.syntax["variables"]
        self.cache = {}

    def meta(self, name):
        for entry in self.syntax["contexts"][name]:
            if "meta_scope" in entry:
                return [entry["meta_scope"]]
        return []

    def rules(self, name):
        if name not in self.cache:
            out = []
            for entry in self.syntax["contexts"][name]:
                if "include" in entry:
                    out.extend(self.rules(entry["include"]))
                elif "match" in entry:
                    entry["_m"] = Matcher(entry["match"], self.variables)
                    out.append(entry)
            self.cache[name] = out
        return self.cache[name]

    def names(self, stack):
        return [scope for name in stack for scope in self.meta(name)]

    def tokenize(self, text):
        stack = ["main"]
        result = []
        for line in text.split("\n"):
            line += "\n"
            scopes = [None] * len(line)
            pos = 0
            guard = 0
            while pos < len(line):
                best = None
                for order, rule in enumerate(self.rules(stack[-1])):
                    m = rule["_m"].search(line, pos, -1, False)
                    if m and (best is None or (m.start(), order) < best[:2]):
                        best = (m.start(), order, rule, m)
                if best is None:
                    paint(scopes, pos, len(line), self.names(stack))
                    break
                start, _, rule, m = best
                paint(scopes, pos, start, self.names(stack))
                before = list(stack)
                if "pop" in rule:
                    stack.pop()
                targets = rule.get("push") or rule.get("set")
                if "set" in rule:
                    stack.pop()
                if targets:
                    stack.extend([targets] if isinstance(targets, str) else targets)
                visible = before if "pop" in rule else stack
                base = self.names(visible)
                if "scope" in rule:
                    base = base + [rule["scope"]]
                paint(scopes, start, m.end(), base)
                for group, scope in rule.get("captures", {}).items():
                    group = int(group)
                    if m.group(group):
                        paint(scopes, m.start(group), m.end(group),
                              base + [scope])
                if m.end() == pos:
                    guard += 1
                    if guard > 50:
                        raise RuntimeError(f"sublime loop at {line!r} {pos}")
                else:
                    guard = 0
                pos = m.end()
            result.append(scopes)
        return result


def parse_yaml(text):
    """Parses the subset of YAML that generate.py emits."""
    lines = [l for l in text.splitlines()
             if l.strip() and not l.lstrip().startswith(("#", "%", "---"))]

    def scalar(raw):
        raw = raw.strip()
        if raw in ("true", "false"):
            return raw == "true"
        if raw.startswith("'"):
            return raw[1:-1].replace("''", "'")
        return raw

    def block(i, indent):
        if lines[i].lstrip().startswith("- "):
            items = []
            while i < len(lines) and indent_of(lines[i]) == indent \
                    and lines[i].lstrip().startswith("- "):
                content = lines[i][indent + 2:]
                if ":" in content and not content.startswith("'"):
                    lines[i] = " " * (indent + 2) + content
                    value, i = block(i, indent + 2)
                    items.append(value)
                else:
                    items.append(scalar(content))
                    i += 1
            return items, i
        mapping = {}
        while i < len(lines) and indent_of(lines[i]) == indent \
                and not lines[i].lstrip().startswith("- "):
            key, _, rest = lines[i].strip().partition(":")
            i += 1
            if rest.strip():
                mapping[key] = scalar(rest)
            else:
                mapping[key], i = block(i, indent_of(lines[i]))
        return mapping, i

    def indent_of(line):
        return len(line) - len(line.lstrip(" "))

    return block(0, 0)[0]


def lexer_tokens(troopl, path):
    out = subprocess.run([troopl, "--tokens", str(path)], capture_output=True,
                         text=True, encoding="utf-8")
    if out.returncode != 0:
        return None
    tokens = []
    for row in out.stdout.splitlines():
        m = re.match(r"(\d+):(\d+): (\w+)", row)
        if m and m.group(3) != "Eof":
            tokens.append((int(m.group(1)) - 1, int(m.group(2)) - 1, m.group(3)))
    return tokens


EXPECTED = {
    "Variable": ("variable.other", "entity.name.variable", "variable.parameter"),
    "Method": ("entity.name.function", "keyword.operator", "support.function"),
    "Number": ("constant.numeric",),
    "String": ("string.quoted",),
    "OpenParen": ("punctuation.section.group", "variable.language.environment"),
    "CloseParen": ("punctuation.section.group", "variable.language.environment"),
    "OpenBlock": ("punctuation.section.brackets",),
    "CloseBlock": ("punctuation.section.brackets",),
    "OpenObject": ("punctuation.section.braces",),
    "CloseObject": ("punctuation.section.braces",),
}


def has(scopes, prefixes):
    return any(s.startswith(p) for s in scopes or [] for p in prefixes)


def check_file(engines, troopl, path, failures):
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    tokens = lexer_tokens(troopl, path)
    if tokens is None:
        return 0
    for name, engine in engines:
        lines = engine.tokenize(text)
        for line, column, kind in tokens:
            scopes = lines[line][column]
            if not has(scopes, EXPECTED[kind]):
                failures.append(f"{name} {path.relative_to(ROOT)}:{line + 1}:"
                                f"{column + 1}: {kind} has {scopes}")
        starts = {(l, c) for l, c, _ in tokens}
        for l, row in enumerate(lines):
            for c, scopes in enumerate(row):
                if has(scopes, ("comment",)) and (l, c) in starts:
                    failures.append(f"{name} {path}:{l + 1}:{c + 1}: token in comment")
    return len(tokens)


# (source, [(text, nth occurrence, expected scope prefix)])
CASES = [
    ("A 1 B C\nD {get X Y (X)}\n(io print D)",
     [("A", 0, "entity.name.variable"), ("1", 0, "constant.numeric"),
      ("B", 0, "entity.name.variable"), ("C", 0, "variable.other"),
      ("D", 0, "entity.name.variable"), ("get", 0, "entity.name.function"),
      ("X", 0, "variable.parameter"), ("Y", 0, "variable.parameter"),
      ("X", 1, "variable.other"), ("io", 0, "support.function.environment"),
      ("print", 0, "entity.name.function.call"), ("D", 1, "variable.other")]),
    ("X m A B", [("X", 0, "variable.other"), ("m", 0, "entity.name.function.call"),
                 ("A", 0, "variable.other"), ("B", 0, "variable.other")]),
    ("(list < 1 , 2 >)", [("list", 0, "support.function"), ("<", 0, "keyword.operator"),
                          (",", 0, "keyword.operator"), (">", 0, "keyword.operator")]),
    ("1+2 3.5- 0inf- 0nan .5 -5", [("1+2", 0, "invalid.illegal"),
                                   ("3.5-", 0, "constant.numeric"),
                                   ("0inf-", 0, "constant.numeric"),
                                   ("0nan", 0, "constant.numeric"),
                                   (".5", 1, "entity.name.function.call"),
                                   ("-5", 0, "entity.name.function.call")]),
    ("Char'0' \"a\"\"b\" # c\nIO/Error' ()",
     [("Char'0'", 0, "entity.name.variable"), ('""', 0, "constant.character.escape"),
      ("# c", 0, "comment"), ("IO/Error'", 0, "entity.name.variable"),
      ("()", 0, "variable.language.environment")]),
    ("a#b\nЯ я", [("a", 0, "support.function"), ("#b", 0, "comment"),
                  ("Я", 0, "variable.other"), ("я", 0, "entity.name.function")]),
    ("O {\n  + Other\n    Third (Other)\n  Inclusion\n}",
     [("+", 0, "entity.name.function"), ("Other", 0, "variable.parameter"),
      ("Third", 0, "variable.parameter"), ("Inclusion", 0, "variable.other")]),
]


def check_cases(engines, failures):
    for source, expectations in CASES:
        for name, engine in engines:
            lines = engine.tokenize(source)
            flat = [s for row in lines for s in row]
            for text, nth, prefix in expectations:
                offset = -1
                for _ in range(nth + 1):
                    offset = source.index(text, offset + 1)
                # Offsets map one-to-one: every line got exactly one "\n".
                if not has(flat[offset], (prefix,)):
                    failures.append(f"{name} case {source!r}: {text!r} has "
                                    f"{flat[offset]}, expected {prefix}")


def main():
    troopl = sys.argv[1] if len(sys.argv) > 1 else str(
        ROOT / "_build" / "default" / "bin" / "main.exe")
    files = [Path(f).resolve() for f in sys.argv[2:]] or sorted(
        p for p in ROOT.rglob("*.tr")
        if "_build" not in p.parts and "doc" not in p.parts)
    textmate = json.loads(
        (HERE / "vscode" / "syntaxes" / "troopl.tmLanguage.json").read_text(
            encoding="utf-8"))
    engines = [("textmate", TextMate(textmate)),
               ("sublime", Sublime(HERE / "sublime" / "TrOOPL.sublime-syntax"))]
    failures = []
    count = sum(check_file(engines, troopl, f, failures) for f in files)
    check_cases(engines, failures)
    for failure in failures[:60]:
        print(failure)
    print(f"{len(files)} files, {count} tokens, {len(CASES)} cases, "
          f"{len(failures)} failures")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
