# Syntax highlighting

Grammars generated from one source (`generate.py`), that follow the
tokenization rules (section 1.7) and grammar (section 2.17) of the
specification:

| File | Used by |
|------|---------|
| `vscode/` | VS Code (TextMate grammar + language configuration), Shiki |
| `sublime/TrOOPL.sublime-syntax` | Sublime Text, `bat`, Typst `raw` blocks |
| `notepad++/TrOOPL.udl.xml`, `TrOOPL_DM.udl.xml` | Notepad++ (light and dark mode) |

## What is highlighted

- comments, strings with `""` escapes, numbers (`1.5-`, `0nan`, `0inf-`);
- digit-led tokens that are not numbers, such as `1+2`, as invalid;
- `()` as the environment;
- definitions (`Name value`), method definitions inside `{}` and their
  parameters, inclusions;
- the method that starts an environment call (`io print`), method calls,
  and method names made only of punctuation (`+ <> -> , :`) as operators.

Tokens end only at whitespace (`[ \t\r\n]`), brackets, `"` or `#`, so names
such as `then-else`, `ok?`, `Char'0'` and `IO/Error'` stay whole, and
double-click selects them in VS Code.

Known limit of the TextMate grammar: it sees one line at a time, so a
definition whose value starts on the next line is shown as a plain variable,
and an environment call is recognised only on the line of its opening
bracket. The Sublime syntax tracks contexts across lines and has only the
first limit.

Notepad++ user-defined languages have keyword lists but no contexts, so the
Notepad++ files colour less:
- variables are words that start with an upper-case Latin, Greek or Cyrillic
  letter;
- the methods of the default environment (`io`, `fs`, `system`, `utf-8`,
  `env`, `eval`, `box`, `array`, `true`, `false`, `core`, `filename`,
  `crash`) are highlighted wherever they appear;
- punctuation-only method names are operators only when spaces surround
  them, as Troopl code normally writes them;
- definitions, parameters and method calls are not told apart;
- brackets fold, and all brackets share one colour.

## Matching brackets

Colouring each bracket pair by nesting depth is an editor feature, not part
of a grammar: a grammar does not know how deep a bracket is.
- VS Code colours bracket pairs by depth out of the box (setting
  `editor.bracketPairColorization.enabled`); it uses the `()`, `[]`, `{}`
  pairs from `language-configuration.json`. `editor.guides.bracketPairs`
  adds vertical guides.
- Notepad++ cannot colour by depth. With the caret next to a bracket it
  highlights that bracket and its partner (Settings > Style Configurator >
  Global Styles > Brace highlight style), and Ctrl+B jumps to the partner.
- Sublime Text needs a package such as BracketHighlighter.

## Install

VS Code: copy or link `editors/vscode` into your extensions folder and reload.

```sh
cp -r editors/vscode ~/.vscode/extensions/troopl
```

Sublime Text: copy `sublime/TrOOPL.sublime-syntax` into the `User` package
(Preferences > Browse Packages).

`bat`:

```sh
mkdir -p "$(bat --config-dir)/syntaxes"
cp editors/sublime/TrOOPL.sublime-syntax "$(bat --config-dir)/syntaxes/"
bat cache --build
```

Notepad++: Language > User Defined Language > Define your language... >
Import, and pick `TrOOPL.udl.xml`, or `TrOOPL_DM.udl.xml` with dark mode on.
Restart Notepad++; `.tr` files then open as TrOOPL. Or copy the file
directly:

```sh
cp editors/notepad++/TrOOPL.udl.xml "$APPDATA/Notepad++/userDefineLangs/"
```

Typst (for example in the specification sources):

```typst
#set raw(syntaxes: "TrOOPL.sublime-syntax")
```

then use ```` ```troopl ```` code blocks.

## Change and check

Edit `generate.py`, never the generated files, then regenerate and check:

```sh
python editors/generate.py
dune build
python editors/check.py
```

`check.py` needs only Python. It runs both grammars with a small TextMate /
Sublime engine over every `.tr` file in the repository and compares each
token with `troopl --tokens`: variables, methods, numbers, strings and
brackets must get the right kind of scope, and nothing the lexer reads may be
inside a comment. It also checks context cases: definitions, parameters,
call-chain arguments, environment calls and operators.
