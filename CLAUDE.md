# dr — Lecture Notes Renderer

## Start Here: Writerly Library

Before working in this repo, read `../../vistuleB/wly/CLAUDE.md`. That file documents:
- The **Writerly** markup language (`.wly` syntax, multi-file assembly, the `WriterlyBlankLine` / `WriterlyCodeBlock` / `WriterlyComment` nodes)
- The **VXML** AST (`V` and `T` nodes, `Blame`, `Attr`, `Line`)
- The **desugaring** library — `Desugarer`, `Pipeline`, `Renderer`, and the full data-flow:
  ```
  Writerly source → List(InputLine) → VXML → VXML (pipeline) → List(OutputFragment) → HTML files
  ```
- The `desugarer_library` API (`dl.*`) and how to read individual desugarer files

## What This Repo Does

`dr` is a **consumer project** of the Writerly/desugaring stack. It renders mathematics lecture notes (courses `235A`, `235B`, `119B`) written in Writerly markup into multi-page HTML.

Language: **Gleam**. Entry point: `src/main.gleam`.

## Project Layout

```
dr/
├── src/
│   ├── main.gleam              # CLI entry point; dispatches to renderer or formatter
│   ├── pipeline.gleam          # THE desugaring pipeline for wly→html rendering
│   ├── renderer.gleam          # HTML emitter; splits VXML into per-page HTML fragments
│   ├── formatter_pipeline.gleam  # Desugaring pipeline for wly→wly formatting
│   └── formatter_renderer.gleam  # Formatter: reads wly, rewraps/normalizes, writes wly back
├── 235A/
│   ├── wly/                    # Writerly source files for course 235A
│   └── public/                 # Generated HTML output for course 235A
├── 235B/
│   ├── wly/
│   └── public/
├── 119B/
│   ├── wly/
│   └── public/
└── shared/                     # Shared static assets (CSS, JS, MathJax setup, etc.)
```

### Source (`wly/`) layout within each course

```
<course>/wly/
├── __parent.wly       # Root document — declares title, course, term, department,
│                      #   institution, lecturer, date, banner attributes
├── 01/                # Chapter 1 (numbered subdirectories = chapters)
│   ├── __parent.wly   # Chapter node
│   ├── 01/            # Section 1.1 (nested subdirs = sections / subsections)
│   └── 02/
├── 02/
└── ...
```

### Output (`public/`) layout

HTML files are named by their structural coordinates, e.g.:
- `1-0.html` — Chapter 1 index page
- `1-1.html` — Chapter 1, Section 1
- `1-2-3.html` — Chapter 1, Section 2, SubSection 3
- `index.html` — course index

## Commands

### Render to HTML

```sh
gleam run -- --which <course_dir> --offline-mathjax
```

`<course_dir>` is a local directory such as `235A`, `235B`, or `119B` that has a `wly/` subdirectory.

`--offline-mathjax` uses the local MathJax asset instead of the CDN URL. This is the default recommended mode; omit it only when CDN access is wanted.

Useful flags:
| Flag | Effect |
|---|---|
| `--which <dir>` | **Required.** Specifies the course directory |
| `--offline-mathjax` | Use local MathJax instead of CDN |
| `--local` | Include source-linking tooltips (requires a local dev server) |
| `--only <path>` | Render only a specific file or subtree |
| `--help` | Print full usage |
| `--esoteric` | Print advanced/esoteric CLI options |

### Authoring rule: a LaTeX row break must never start a line

**When converting `.tex` → `.wly`, never begin a line with a row break followed by
whitespace** (`\\ &= ...`). Writerly's beginning-of-line escape (`wly/writerly/src/writerly.gleam`,
`includes_bol_te_escape = "^\\\\+(\\s|!!|```)"`) treats one-or-more leading backslashes
before whitespace as an escape and strips one, so `\\ &= x` silently becomes `\ &= x`.
The row break vanishes and a multi-row aligned derivation collapses into a single
over-wide row. This is parser behaviour by design — put the row break at the **end of the
previous line** instead:

```
\begin{eqnarray*}
C_\infty &=& \textrm{“for all $N\ge 1$, $D_N$ occurred”} \\
&=& D_1 \wedge D_2 \wedge D_3 \wedge \ldots \\
&=& \bigwedge_{N=1}^\infty D_N
\end{eqnarray*}
```

Equivalently: if a row break must lead a line, ensure it is **not followed by whitespace**.
Two forms are already safe — a line that is exactly `\\` (nothing after it, so no match)
and `\\[5pt]` (`[` is not whitespace).

### Authoring rule: escaping `_` and `*`

To write a literal underscore or asterisk in prose without triggering italics/bold,
prefix it with a backslash: `\_` and `\*`. The backslash is consumed and does not
appear in the output. This is handled by
`dl.unescape_delimiters__outside(["_", "*"], ["Math", "MathBlock"])`, which runs
**after** both `barbaric_symmetric_delim_splitting` steps — anything added to the
pipeline that splits on a delimiter must go before it, or the escape will be re-armed.

Deliberately **not** escapable:

- **`$`** — math is emitted as literal `$…$` for browser-side MathJax, so a bare `$`
  in prose would open math in the reader's browser. Write `\$` and it stays `\$`.
- **`\` itself** — these documents use a trailing `\\` as a LaTeX row break in ordinary
  prose, and collapsing `\\`→`\` corrupts them. Consequence: a literal backslash
  directly in front of a live delimiter is not halved (`\\_x_` → `\\<i>x</i>`).
- **`\(` and `\[`** — the delimiter itself begins with a backslash, so `\\(` is
  ambiguous between "escaped delimiter" and "literal backslash then `(`".

Italics inside a link (`[really _emphatic_ text](url)`) are legitimate and still work;
the escape is the mechanism for suppressing a delimiter, not tag-based scoping.

### Post-render verification

MathJax reports **no error** for the bug above — a lost `\\` yields valid-but-wrong TeX —
so the usual `mjx-merror === 0` plus `mjx-container > 0` assertions provably do **not**
catch it. Always also grep the rendered HTML:

```sh
# row breaks eaten by the BOL escape; note the output is INDENTED,
# so this must not be anchored at column 0
grep -rnE '^[[:space:]]*\\[[:space:]]' <course>/public/*.html
```

Expect a handful of benign hits where the source legitimately begins a line with a single
`\ ` (a LaTeX control space, which the escape correctly consumes) — currently 3 in 235A
and 1 in 235B. Anything of the shape `\ &=` or `\ \textrm{` is a real eaten row break.
Do not use `^\\ (&amp;|&)`: it anchors at column 0 (matching nothing) and misses rows
that begin with something other than `&`.

### Format Writerly source in-place

```sh
gleam run -- --which <course_dir> --fmt [<cols>] [<cols> <penalty>] [-file <name>]
```

Reads `.wly` files from `<course_dir>/wly/`, rewraps and normalizes them, and writes them back to `<course_dir>/wly/`. Options:
- `<cols>` — preferred line length (default 55)
- `<cols> <penalty>` — line length + indentation penalty (chars subtracted per indent level)
- `-file <name>` — format only a single named file

### Local dev server

```sh
COURSE=235A npm run dev        # serves on localhost:3003
PORT=3004 COURSE=235B npm run dev
```

Configure defaults in a `.env` file at the project root:
```
COURSE=235A
OFFLINE_MODE=true
MATHJAX_VERSION=3
```

## Pipeline (`src/pipeline.gleam`)

The desugaring pipeline (`pub fn pipeline(course: String)`) transforms the parsed VXML tree into HTML-ready VXML. Key stages in order:

1. **Tag validation** — `check_tags` against a pre-transformation approved list
2. **Cleanup** — `delete("WriterlyComment")`, `delete_attribute_if` for `!!`-prefixed keys, `unwrap_if_first_child`
3. **QED / proof boilerplate** — appends QED symbol node to `Proof` tags, wraps proof labels
4. **Semantic renaming** — `Definition`, `Example`, `Exercise`, `Lemma`, `Theorem` → `Statement` with `class` and `title` attributes
5. **Counters** — appends counter attributes to `Document`, `Chapter`, `Section`; increments `ChapterCounter`, `SectionCounter`, `SubSectionCounter`, `StatementCounter`
6. **Auto-generate titles** — `auto_generate_child_if_missing_from_attribute` for `ChapterTitle`, `SectionTitle`, `SubSectionTitle`
7. **Index & menu creation** — `dr_create_index()`, `dr_create_menu()` (project-specific desugarers)
8. **Counter text injection** — `prepend_text_node__batch` (e.g. "1.3 " before section titles)
9. **Math block parsing** — via `pp.create_mathblock_elements` (`$$`, `\begin{align}`, `\begin{align*}`)
10. **Inline math parsing** — via `pp.create_math_elements` (`\(`, `$`)
11. **Italic/bold splitting** — `pp.barbaric_symmetric_delim_splitting` for `_..._` → `<i>` and `*...*` → `<b>` (skipping math nodes)
12. **Smart quotes** — `find_replace_if_has_ancestor_else` for ` `` ` → `"` and `''` → `"` (aware of Math context)
13. **Paragraph grouping** — `group_consecutive_children__outside` (groups inline content into `<p>` tags)
14. **Cleanup** — `unwrap("WriterlyBlankLine")`, `trim("p")`, `delete_if_empty("p")`
15. **Class assignment** — `append_class__batch` for `MathBlock`, `Index`, `Chapter`, `Section`, `SubSection`
16. **JS course data** — `dr_generate_js_course(course)` injects course metadata for the frontend
17. **Final rename** — all semantic tags renamed to HTML tags: `Chapter`→`div`, `ChapterTitle`→`h1`, `MathBlock`→`div`, `Proof`→`div`, `Statement`→`div`, etc.
18. **Attribute cleanup** — `delete_attribute__batch` removes internal attributes (`_`, `counter`, `title`)
19. **Post-transformation tag validation** — `check_tags` against the HTML-only approved list

### Document tags (pre-transformation)
`Chapter`, `ChapterTitle`, `Definition`, `Document`, `Example`, `Exercise`, `Labeled`, `Lemma`, `Proof`, `Section`, `SectionTitle`, `SubSection`, `SubSectionTitle`, `Theorem`, `WriterlyBlankLine`, `footnote`, `li`, `ol`, `ul`

### HTML tags (post-transformation)
`Document`, `a`, `b`, `br`, `div`, `h1`, `h3`, `header`, `i`, `li`, `ol`, `p`, `span`, `ul`

## Renderer (`src/renderer.gleam`)

`pub fn render(amendments, course_dir)` orchestrates the full wly→HTML pipeline:

1. Reads `<course_dir>/wly/__parent.wly` to extract document metadata (`title`, `course`, `term`, `department`, `institution`, `lecturer`, `date`, `banner`)
2. Runs the pipeline (`pipeline.pipeline(course_dir)`)
3. Splits the VXML tree into fragments by structural type (`FragmentType`):
   - `Index` → `index.html`
   - `Chapter(n)` → `n-0.html`
   - `Section(ch, sec)` → `ch-sec.html`
   - `SubSection(ch, sec, sub)` → `ch-sec-sub.html`
4. Emits each fragment via the appropriate emitter (`index_emitter`, `chapter_emitter`, `section_emitter`, `subsection_emitter`)
5. Cleans up stale `.html` files from `public/` before writing new output
6. Output goes to `<course_dir>/public/`

`filename_shorthand_to_path_fragment` allows `--only 1.2` as shorthand for the path `01/02/__parent.wly`.

## Formatter (`src/formatter_pipeline.gleam`, `src/formatter_renderer.gleam`)

The formatter is a **wly → wly** pass (not wly → HTML). It normalizes and rewraps Writerly source files in-place.

`formatter_pipeline.gleam` — defines `pub fn formatter_pipeline(line_length, indentation_penalty)`:
- Parses math blocks and inline math (same as the main pipeline)
- Removes internal/test attributes
- Rewraps text lines via `dl.line_rewrap_no2__outside` (respects `Chapter`/`Section`/`SubSection` indentation hierarchy and skips `MathBlock`, `pre`, `WriterlyCodeBlock`)
- Normalizes blank-line spacing between structural elements (`add_between`, `add_if_missing_before_but_not_before_first_child`)
- Unwraps `p` and `MathBlock` back to plain Writerly before writing

`formatter_renderer.gleam` — drives the formatter loop, reads from `<course_dir>/wly/`, writes back to `<course_dir>/wly/` (or a custom `--output-dir`). Can target a single file with `-file`.

### Every source tag must appear in `p_cannot_contain`

`formatter_pipeline.gleam`'s `p_cannot_contain` list must name **every tag that can appear
in a `.wly` source file**. A tag missing from it is not treated as a paragraph barrier, so
`group_consecutive_children__outside` wraps the whole element *inside* a `p` — and because
`p_cannot_be_contained_in` contains `"p"`, nothing beneath it is ever grouped into paragraphs.
The later `add_between(#("p", "p", "WriterlyBlankLine"))` then has no `p` siblings to work
with, and **every blank line inside that subtree is silently deleted**, merging paragraphs.

This is easy to miss because the main `pipeline.gleam` renames `Definition`/`Lemma`/… to
`Statement` *before* grouping, so its list gets away with the post-rename names. The formatter
does no such renaming and needs the raw authored names. When adding a tag to
`src/pipeline.gleam`'s pre-transformation approved list, add it to `formatter_pipeline.gleam`'s
`p_cannot_contain` too.

Verify with a round-trip: format to a scratch dir, render both source and formatted output to
HTML, and compare with whitespace collapsed (`tr -s ' \t\n' ' '`). The two must be identical —
formatting must never change rendered output.

### Known limitation: nested `$` inside `\textbf{…}`

Constructs like `$\textbf{$\sigma$-algebra}$` may get a line break inserted at the inner
`$`…`$` junction, which renders as a visible space (`σ -algebra`). The `$`-splitter reads
this as *two* adjacent `Math` nodes joined by a text node, and
`dl.wrap_adjacent_non_whitespace_text_with` builds a separate `NoWrap` group per `Math`
instead of one spanning group, leaving a legal break point between them. Fixing it means
changing that desugarer in `wly/desugaring/`, which is also used by `courses`' and
`little-bo-peep-solid`'s **HTML** pipelines. Affects 6 of 235A's 73 pages; 235B and 119B
are unaffected.

### Convergence

Formatting is content-stable on the first pass but layout-stable only from the second: a
first run over never-formatted source can leave a few lines wrapped shorter than the target,
which a second run rejoins. Pass 2 == pass 3, and pass 1 → pass 2 changes line breaks only.

## Writerly Repo Location

The Writerly/desugaring library lives at `../../vistuleB/wly/` (relative to this project root). This project imports it as a local Gleam dependency. When adding or modifying desugarers, check `../../vistuleB/wly/desugaring/src/desugarer_library.gleam` for the full list of available `dl.*` functions.
