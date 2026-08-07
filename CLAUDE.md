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

### Render to LaTeX / PDF

```sh
gleam run -- --which <course_dir> --latex             # one monolithic <course>.tex
gleam run -- --which <course_dir> --latex-chapter     # main.tex + one file per chapter
gleam run -- --which <course_dir> --latex-section     #   ...chapters that \input sections
gleam run -- --which <course_dir> --latex-subsection  #   ...sections that \input subsections
```

**Modularity (`Granularity` in `latex_renderer`).** `--latex` emits **one
self-contained `<course>.tex`**. The three modular flags emit a
`main.tex` (preamble + title + TOC) that `\input`s the body across files:
`chapters/N.tex`, and at finer granularities `sections/N-M.tex` /
`subsections/N-M-P.tex`, plus **one file per standalone unit** (`exercises.tex` /
`bibliography.tex`, emitted in document order — so last). A structural unit at
depth *level* (chapter 1, section 2, subsection 3) becomes its own file when
`level <= max_split(granularity)`, else it is inlined exactly as the monolithic
emitter would (`modular_unit`/`modular_children`). `default_writer` auto-creates
the `chapters/`, `sections/`, `subsections/` subdirs. **Compile `main.tex`** for
modular output, `<course>.tex` for monolithic. Footnote/equation numbers stay
global (one shared `build_ctx` across all files).

Emits, for the monolithic case, **one self-contained `.tex` file** at
`<course_dir>/latex/<course_dir>.tex` (e.g. `235A/latex/235A.tex`) that compiles
with `pdflatex` into a PDF with a clickable table of contents and a PDF bookmark
outline. Each run first
**clears the whole `<course_dir>/latex/` directory** (via `simplifile.clear_directory`
in `latex_renderer.render`) so stale pdflatex leftovers (`.toc`/`.aux`/`.log`/
`.out`/`.pdf`) never linger; the `.tex` is regenerated and `figures/` re-copied
(so changed source images are picked up). Compile with three passes (TOC +
cross-references need to settle):

```sh
cd <course_dir>/latex && pdflatex 235A.tex && pdflatex 235A.tex && pdflatex 235A.tex
```

**The multi-pass compile is mandatory, not optional.** After pass 1 there is no
`.aux`, so hyperref cannot resolve TOC/cross-reference targets and emits almost
**no `/Link` annotations** (≈5, vs ≈170 once settled) — the PDF looks link-less.
Always grab the PDF after the *last* pass, and sanity-check link count before
trusting it (`/Subtype /Link` occurrences). Note: **ghostscript** (and anything
built on it, e.g. ImageMagick `convert`) chokes on the TOC page with a "Page
drawing error" once Latin Modern is in use — that is a gs rasterizer bug only;
real viewers (Preview/Chrome/Acrobat) render the page and its blue links fine, so
verify visuals in an actual viewer, not via gs.

This is a **separate, idiomatic-LaTeX path** from the HTML renderer, not a
variant of it (`src/latex_pipeline.gleam` + `src/latex_renderer.gleam`, wired
into `main.gleam` alongside `--fmt`). Design:

- **`report` document class.** `Chapter` → `\chapter`, `Section` → `\section`,
  `SubSection` → `\subsection`; `\tableofcontents` + `hyperref`/`bookmark` give
  the clickable TOC and the outline for free. The standalone appendix units
  `Exercises` (235A) and `Bibliography` (119B's "Bibliographic notes") → an
  unnumbered `\chapter*` + `\addcontentsline` (title read from the tag's `title`
  attr), so they sit outside the numbered chapter sequence but still appear in
  the TOC + outline.
- **Native LaTeX numbering** (not the web's baked counters). Theorem-like tags
  (`Definition`/`Theorem`/`Lemma`/`Corollary`/`Example`/`Exercise`) map to
  shared-counter `amsthm` `\newtheorem` environments (`[chapter]`-scoped, so
  `Theorem 2.1` etc. match the source); `Proof` → `proof` (auto QED). A tag's
  `label=` becomes the theorem note `[...]`, its `handle=` becomes `\label{}`.
- **Cross-references become native.** `>>handle` → `\ref{handle}`; footnote
  markers `(*>>h)` are inlined as `\footnote{}` (the `Footnote` block + its `hr`
  are dropped).
- **Equation numbering is identical to the HTML renderer.** The web numbers only
  the `name##<<`-marked equations, globally and sequentially (Writerly's
  `::++EquationCounter`), rendered as `\tag{N}`; manual mnemonic tags (`\tag{A1}`,
  …) are kept; everything else is unnumbered. The LaTeX path reproduces this
  exactly: a pre-pass (`collect_eq_labels`) numbers the k-th `name##<<` marker in
  document order as equation *k*, and each marker is emitted as
  `\tag{N}\label{name}` (so `\ref` resolves to the same N). To prevent LaTeX's own
  auto-numbering from adding *extra* numbers, `mathblock_to_latex` emits every
  standalone display environment in its **starred** form — the visible numbers
  come only from the `\tag`s. Since `\tag` is illegal in the legacy `eqnarray`,
  a *tagged* `eqnarray[*]` is converted to `align*` with its `& REL &` columns
  collapsed to `& REL` (`eqnarray_to_align`; safe because tagged eqnarrays here
  never nest a `&`-using env). This equality is regression-checkable: extract
  `\tag{\d+}` from the HTML pages in document order and from the `.tex`; the two
  sequences must be identical (currently `1..30`).
- **Math passes through verbatim** (it is already LaTeX): the emitter only
  strips the `$$` the pipeline wraps around a display block, then emits the inner
  environment directly or wraps bare math in `\[ ... \]`. Custom macros the
  source still uses (`\R`, `\Z`, `\prob`, `\cal`, …) are declared in the preamble
  built by `latex_renderer.preamble`.
- **Overflow control.** Wide display tables (a bare `$$…$$` display containing a
  `\begin{array}`, e.g. the "Summary of special distributions" grid) are routed
  through `\fitwidth` (a `\sbox`+`\ifdim`+`\resizebox` macro) so they scale down
  to `\linewidth` only when too wide, and otherwise render at natural size. For
  running text, `microtype` + `\emergencystretch=3em` absorb the source's long
  unbreakable `$\textbf{…}$` prose phrases that would otherwise run off the right
  margin. Vector fonts come from `\usepackage{lmodern}` (before `[T1]{fontenc}`);
  without it, this TeX install falls back to blurry Type-3 bitmap Computer Modern.
- **Figures.** A `figure` becomes a centered, non-floating block whose panels flow
  side by side and **wrap to a grid** when a row exceeds `\linewidth` (breakable
  `\hspace` between panels in a `center`). Two source shapes are handled: a direct
  `img` → `\includegraphics[width=0.N\linewidth]{src}` (235B; width from
  `style=max-width: N%`), and a `span`(width%){ `img` + label } → a top-aligned
  `minipage` panel with the image at full box width and its "(a)"/"(b)" label
  below (119B's multi-panel figures). The `figcaption` renders as small centered
  text below. Figures are NOT `\caption`/`figure` floats: the source hard-numbers
  them ("Figure 1:", …) in the caption text and refers to them by that literal
  number in prose, so LaTeX auto-numbering would clash. The renderer copies the
  course's `public/figures/` next to the emitted `.tex` (`copy_figures`) so the
  `figures/<name>` paths resolve and the bundle is self-contained. `graphicx`
  handles `.png`/`.jpg`/`.jpeg`.
- **All three courses work: 235A, 235B, 119B.** URLs are escaped for the `\href`
  URL argument (`escape_url`: `#`→`\#`, `%`→`\%`) — a raw `#` in an href inside a
  `\footnote` otherwise errors ("Illegal parameter number"). 119B's "Parts" are
  `\chapter`s titled "Part N — …" (keeps the `[chapter]`-scoped theorem numbering
  working); no custom macros beyond `\R` (its `\Y`/`\F`/`\a` were `\\`+letter row
  breaks, not macros).

Note: **ghostscript cannot rasterize the `\resizebox` (fit) pages or the
Latin-Modern TOC** ("Page drawing error") — a gs bug, not a PDF defect. Verify
those pages with a real renderer: the in-app browser, or macOS `sips` (Quartz) on
a single page extracted with `gs -sDEVICE=pdfwrite -dFirstPage=N -dLastPage=N`.

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

### Display-math delimiter normalization (the `$$` opinion)

The formatter recognizes **every standalone LaTeX display environment** as a block and applies a
per-environment `$$` opinion. Both are driven by one editable table,
`display_delimiter_dollar_policy()` in `src/formatter_pipeline.gleam` — a
`List(#(LatexDelimiterPair, Bool))` with **one row per environment**, the boolean meaning
`True` = wrap the block in `$$`, `False` = leave it bare:

```gleam
#(infra.BeginEndAlign, False),          // bare
#(infra.BeginEndAlignStar, False),      // bare
#(infra.BeginEndEnvironment("equation"), True),   // $$-wrapped
#(infra.BeginEndEnvironment("gather"), True),
// … alignat(*), flalign(*), multline(*), eqnarray(*), equation* …
```

Two helpers derive from it: `recognized_display_delimiters()` (all rows → fed to
`create_mathblock_elements` so a **bare** environment is captured as math instead of being
line-wrapped as prose, which silently corrupts it) and `bare_display_openings()` (the
`\begin{…}` tokens of the `False` rows → the `strip_delimiters_inside_if` predicate strips `$$`
off exactly those). Matching is by the exact `\begin{env}` token (with its closing brace), so
`\begin{align}` never matches `\begin{alignat}` or the subsidiary `\begin{aligned}`.

- **Standalone** environments create their own display math and may legally appear bare:
  `equation(*)`, `align(*)`, `alignat(*)`, `flalign(*)`, `gather(*)`, `multline(*)`,
  `eqnarray(*)` — these are the policy rows.
- **Subsidiary** environments (`split`, `aligned`, `cases`, `array`, `matrix`/`pmatrix`/…,
  `gathered`, `subarray`) are only valid *inside* math mode; they are **not** in the table and
  simply ride along inside their enclosing `$$` block.

**Default opinion:** `align` / `align*` are the only rows set `False` (bare); every other
environment is `$$`-wrapped (each `$$` on its own line).

**Any row may be flipped to bare.** The HTML renderer (`src/pipeline.gleam`) reuses
`recognized_display_delimiters()` in *its own* `create_mathblock_elements` call, so it wraps
**every** standalone display environment in `$$` (if not already) before MathJax sees it. A bare
`\begin{eqnarray*}` / `\begin{equation}` / … in source is therefore re-wrapped and typeset
correctly. (Without this, a bare environment falls through to the prose pipeline, which mangles
it — the `*` in `eqnarray*` bold-splits, `_` subscripts italic-split — and MathJax then renders
it as raw literal text.) Whether an environment appears bare or `$$`-wrapped in the **source** is
purely the formatter's cosmetic choice; the rendered HTML is correct either way. This shared
recognition set is the invariant that keeps the renderer able to accept whatever `--fmt` emits.

The parametric delimiter lives in `wly`: `LatexDelimiterPair.BeginEndEnvironment(name)` and its
`BeginEnvironment`/`EndEnvironment` singletons (`wly/desugaring/src/infrastructure.gleam`), with
splitter arms in `prefabricated_pipelines.gleam`. `wly` provides only the *mechanism*; the list
of environments and their `$$` flags is consumer policy, living wholly in the formatter table.
All string-based delimiter consumers (`strip_delimiters_inside*`, `normalize_*`) work through
`opening_and_closing_string_for_pair` and needed no change.

**Known cosmetic effect:** a run of *consecutive bare* `\begin{equation}` blocks (as in
235A `02/01-basic-definitions.wly`) becomes separate `$$`-wrapped math-blocks with normal
inter-block spacing, rather than the tight cluster the bare form rendered as. Math content is
unchanged and MathJax reports no error; only vertical spacing differs.

## Writerly Repo Location

The Writerly/desugaring library lives at `../../vistuleB/wly/` (relative to this project root). This project imports it as a local Gleam dependency. When adding or modifying desugarers, check `../../vistuleB/wly/desugaring/src/desugarer_library.gleam` for the full list of available `dl.*` functions.
