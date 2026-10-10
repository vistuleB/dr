# dr

Writerly course notes for **235A, 235B, and 119B**, rendered to HTML or LaTeX.
Run commands from this repository's root.

## Quick start

Install Gleam and Erlang/OTP for the renderer, and Node.js with npm for the local
server. The installed Vite 8 dependency requires Node.js `^20.19.0 || >=22.12.0`.

```sh
gleam deps download
npm ci
gleam run -- --which 235A --local
npm run dev -- --course 235A
```

Open the URL printed by the server. Substitute `235B` or `119B` in both commands
to work on another course. The renderer and server select their courses
independently. Rerun Gleam after editing `.wly` source; the server does not run it.
For HTML intended for publication, render without `--local` to omit author
source-linking tooltips.

## Project layout and renderer API

| Path | Role |
|---|---|
| `<course>/wly/` | Writerly source, rooted at `__parent.wly` |
| `<course>/public/` | Generated HTML, course assets, and links to shared assets |
| `<course>/latex/` | Generated LaTeX and copied figures |
| `shared/` | CSS, browser JavaScript, and local MathJax assets shared by all three courses |
| `src/main.gleam` | CLI handling and dispatch to HTML, formatter, or LaTeX rendering |
| `src/renderer.gleam`, `src/pipeline.gleam` | HTML renderer and its desugaring pipeline |
| `src/latex_renderer.gleam`, `src/latex_pipeline.gleam` | LaTeX output |
| `src/formatter_renderer.gleam`, `src/formatter_pipeline.gleam` | Writerly source formatting |
| `src/desugarers/` | Project-specific desugarers |
| `src/local_desugarers.gleam` | Generated registry of local desugarers and tests |
| `scripts/`, `vite.config.js` | Local server startup, checks, and tooltip launch handling |

The project uses published `writerly`, `vxml`, and `vxml_pipeline` packages;
no sibling `wly/desugaring` checkout is required. `gleam.toml` requires
`vxml_pipeline >= 0.4.3`, and `manifest.toml` records resolved versions.

The current Gleam API uses `vxml_pipeline.Renderer`, `RendererParameters`, and
`RendererOptions`. A `vxml_pipeline/core.Pipeline` is a list of `Desugarer`
values. `vxml_pipeline/desugarers` supplies shared transformations;
`local_desugarers` supplies this project's additions. Delimiter helpers come
from `vxml_pipeline/delimiter_pipelines`, imported as `delimiters`.

The renderer is assembled from an assembler, parser, filterer, pipeline,
splitter, emitter, writer, and prettifier, then invoked with
`ds.run_renderer(renderer, parameters, options)`. Writerly adapters live in
`vxml_pipeline/writerly_defaults`: `default_writerly_assembler`,
`default_writerly_parser`, and `default_writerly_emitter`. The HTML renderer
uses its own splitter and emitter; the formatter uses the Writerly emitter.

## Commands and maintenance

```sh
gleam run -- --help
gleam run -- --track-help
gleam run -- --which 235A --table
gleam run -- --which 235A --local --offline-mathjax
```

`--which` selects the course for rendering and formatting. `--input-dir` is
rejected by this project's CLI. For HTML, `--output-dir preview` writes beneath
the selected course (`235A/preview/` in this example); it does not copy the
public assets into that directory.

The formatter rewrites `.wly` source in place by default. Its default line length
is 55, with no indentation penalty:

```sh
gleam run -- --which 235A --fmt
gleam run -- --which 235A --fmt 70 2
```

After adding a desugarer under `src/desugarers/`, regenerate the registry and
run its tests. These maintenance commands do not require `--which`:

```sh
gleam run -- --generate
gleam run -- --renumber
gleam run -- --desugarer-tests
gleam run -- --desugarer-tests dr_normalize_image_grids
gleam run -m local_desugarer_tests
```

`--desugarers` combines blame renumbering, registry generation, and desugarer
testing. Use `gleam build` to check compilation and `npm run test:dev` for the
local-server tests.

## `--last-command` (VSCode build task integration)

The `--last-command` flag replays arguments from the local `.last-command` file.
The HTML command writes this file **before** rendering, so a failed render can
also become the saved command. Help, maintenance, formatter, and LaTeX runs do
not replace it. Use `--last-command` on its own, without additional flags.

The sample VS Code task provides a default build task (Cmd+Shift+B on macOS).
It does not by itself enable running on every save; that requires separate
editor automation. Create `.vscode/tasks.json` from the sample:

```sh
mkdir -p .vscode
cp sample_tasks_dot_json.json .vscode/tasks.json
```

The task runs `gleam run -- --last-command`, which picks up whatever flags you last used
(e.g. `--which 235A --offline-mathjax`). The first time you run with `--last-command` you
must have invoked HTML rendering at least once without it so that a
`.last-command` file exists.

The `.last-command` file and `.vscode/` directory are already ignored by Git.

## PDFLaTeX

On MacOS, install pdflatex with `brew install --cask basictex`

Generate the LaTeX source for a course with `gleam run -- --which 235A --latex-monolithic`
(writes `235A/latex/main.tex`), then convert it to a PDF with `pdflatex main.tex`.

### LaTeX output flags

One flag per run selects how finely the source is split across files. Every flag
requires `--which <course>` and writes into `<course>/latex/`. The output root is
**always `main.tex`** (preamble + title + clickable TOC) — that is the file you
compile, whatever the granularity. There is **no bare `--latex`**; use one of:

| Flag | Output |
|---|---|
| `--latex-monolithic` | one self-contained `main.tex`, nothing else |
| `--latex-chapters` | `main.tex` + one file per chapter under `chapters/` |
| `--latex-sections` | chapters that have sections become folders that `\input` one file per section |
| `--latex-subsections` | sections that have subsections become folders that `\input` one file per subsection |

If several are given, the **finest wins**. Each run first **clears the whole
`<course>/latex/` directory** (so stale `.tex` and pdflatex leftovers never
linger), then regenerates `main.tex` (+ the `chapters/` tree) and re-copies
`figures/`.

**Example** — `gleam run -- --which 235A --latex-subsections` (abridged tree):

```
235A/latex/
├── main.tex                              # compile THIS
└── chapters/
    ├── 01/
    │   ├── 01.tex                        # a folder NN/ always holds its own NN.tex
    │   └── sections/
    │       ├── 1.tex                     # 2 sections → unpadded 1.tex, 2.tex
    │       └── 2.tex
    ├── 05.tex                            # sectionless chapter stays a plain file
    ├── 08/
    │   ├── 08.tex
    │   └── sections/
    │       └── 01.tex … 11.tex           # 10+ sections → zero-padded 01.tex
    ├── 14/
    │   ├── 14.tex
    │   └── sections/
    │       ├── 1.tex                     # leaf section (no subsections) → a file
    │       └── 2/                        # section WITH subsections → a folder
    │           ├── 2.tex
    │           └── subsections/
    │               └── 1.tex … 3.tex
    └── exercises.tex                     # standalone units → their own leaf file
```

Layout rules:

- A numbered folder `NN/` always contains its own `NN.tex` root file.
- A unit becomes a **folder only when it actually has sub-parts to split out** —
  a childless chapter/section stays a plain `.tex` file (never an empty folder).
- Names in a directory start at `1` and are **zero-padded to `01`/`02`/… only
  when that directory holds 10 or more items**, else plain (`1`, `2`, …).
- Standalone units (235A's Exercises, 119B's Bibliography) get their own leaf
  file (`chapters/exercises.tex`, `chapters/bibliography.tex`) in document order
  — except under `--latex-monolithic`, where they stay inline in `main.tex`.

Only `main.tex` has a preamble, so **always compile `main.tex`** — the per-chapter
files are `\input` fragments and will not compile on their own.

**Run `pdflatex` three times.** The Table of Contents is typeset from the `.toc`
file, which LaTeX only *writes* during a run, so the passes converge like this:

1. **Pass 1** — no `.toc` exists yet, so the Contents page is **blank**. LaTeX
   writes a `.toc`, but with page numbers computed *without* the (still-absent)
   Contents pages.
2. **Pass 2** — the Contents now appears, which pushes the whole document down by
   the Contents' own length (~2 pages), but the page numbers it *shows* are the
   stale ones from pass 1 — so **every TOC page number is off by ~2**. LaTeX
   prints `Rerun to get cross-references right`.
3. **Pass 3** — the page numbers settle and the warning disappears.

This is standard LaTeX behaviour, not a bug — a document with a TOC needs the
extra pass whenever the TOC changes the pagination. Rule of thumb: **rerun until
the `Rerun to get …` warning stops** (three times here). The PDF outline and any
cross-references settle the same way.

```sh
cd 235A/latex && pdflatex main.tex && pdflatex main.tex && pdflatex main.tex
```

`latexmk -pdf main.tex` does the reruns for you automatically (install it with
`tlmgr install latexmk` if it isn't already available).

### Forcing a paragraph indent (`|> Indent`)

In the LaTeX output, the first line of the paragraph right after a display, list,
or theorem-like block is **not** indented (the emitter inserts `\noindent`) —
that paragraph is a continuation. Only a paragraph following another paragraph
takes the usual first-line indent. If you *want* the post-block paragraph
indented anyway, put a bare `|> Indent` tag immediately before it:

```
$$ ... $$

|> Indent

This paragraph will be indented (\indent in LaTeX; class="indent" in HTML).
```

The marker is consumed during rendering. It emits `\indent` on the LaTeX side and
adds an `indent` class to the paragraph on the HTML side (currently styled as a
no-op, since these notes separate paragraphs with blank lines rather than
indents).

## Shared assets

All three courses already link `app.css`, `local.css`, `app.js`,
`mathjax_setup.js`, and `tex-svg.js` to the corresponding files in `shared/`.
Edit those shared files once to update all courses.

For a new shared asset, put it in `shared/` and create a relative symlink in each
course that uses it. For example, when the destination does not already exist:

1. `cd` into project root
2. `ln -s ../../shared/mathjax_setup.js 235A/public/mathjax_setup.js`

## Running the local server

Install the Node dependencies with `npm ci`. Generate HTML before serving it:

```sh
gleam run -- --which 235A --local
npm run dev -- --course 235A
```

The server serves `<course>/public/` at `http://127.0.0.1:3003`. It does not
regenerate Writerly sources: rerun Gleam after editing `.wly` files.

These commands work without shell-specific environment assignment syntax:

```sh
npm run dev -- --course 235B --port 3010
npm run dev:mobile -- --course 119B
npm run dev -- --course 119B --host 0.0.0.0
npm run dev -- --help
```

`dev:mobile` listens on the local network. For author tooltips on a phone, scan
the QR code printed by the server; its authorization token changes on restart.
Source tooltips require the `code` command on the server's PATH. Image-opening
currently uses macOS's `open`; portable startup does not yet imply Windows
support for tooltip app launching or Git symlink checkout.

Defaults can be set in the repository's `.env`:

```dotenv
COURSE=235A
HOST=127.0.0.1
PORT=3003
```

Precedence: command-line options, then shell environment variables, then `.env`,
then the defaults above. Existing macOS/Linux commands such as
`COURSE=235B npm run dev` still work. Unknown options, missing values, invalid
ports, and occupied ports produce errors; the server does not silently pick
another port (the author-tooling URLs must match).

MathJax selection happens when generating HTML: add `--offline-mathjax` to the
Gleam command to use the local copy. `OFFLINE_MODE` and `MATHJAX_VERSION` are not
server settings.

Run the dev-launcher tests with `npm run test:dev`.

### Startup checks and tooltip failures

Startup checks for generated `index.html` and all five shared assets (`app.css`,
`local.css`, `app.js`, `mathjax_setup.js`, `tex-svg.js`). Missing/broken links,
links to the wrong shared file, and Git symlinks checked out as plain text produce
an error with repair instructions. On Windows, enable Developer Mode and Git's
`core.symlinks` support before checking out the links. Actual copies also work,
but must be kept synchronized with `shared/`.

Tooltips accept image paths containing spaces. The server waits for the launcher
command to finish before reporting success; failures appear in a browser alert.
A successful launcher exit confirms command completion, not that the GUI app
finished loading the file. Missing `code` produces setup instructions. Image
opening on Windows/Linux and source opening on Windows currently report an
explicit unsupported-platform message rather than attempting an incompatible
command. These diagnostics are tested using simulated platforms on macOS;
Windows GUI launching has not been verified.

On macOS, image tooltips use the default application for each file type. To change
it: select a file in Finder, choose **Get Info (⌘I) → Open with**, select the app,
and click **Change All…**. Repeat for SVG, PNG, JPEG, etc. Source-text tooltips
explicitly use VS Code (`code --goto`), independently of the default `.wly` app.
