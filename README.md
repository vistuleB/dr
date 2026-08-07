# `--last-command` (VSCode build task integration)

The `--last-command` flag reruns the exact same arguments as the previous successful run,
reading them from a local `.last-command` file written automatically at the end of each run.

This is useful when combined with a VSCode build task that fires on every `.wly` file save.
Create `.vscode/tasks.json` in the project root (you can copy `sample_tasks_dot_json.json`
from this repo as a starting point):

```sh
cp sample_tasks_dot_json.json .vscode/tasks.json
```

The task runs `gleam run -- --last-command`, which picks up whatever flags you last used
(e.g. `--which 235A --offline-mathjax`). The first time you run with `--last-command` you
must have run the renderer at least once without it so that a `.last-command` file exists.

The `.last-command` file is local; add it to `.gitignore` if you do not want it committed.

# PDFLaTeX

On MacOS, install pdflatex with `brew install --cask basictex`

Generate the LaTeX source for a course with `gleam run -- --which 235A --latex`
(writes `235A/latex/main.tex`), then convert it to a PDF with `pdflatex main.tex`.

You can also split the source into multiple files, depending on how you want to
modularise. The output root is **always `main.tex`** (the file you compile):

- `--latex` — one long `main.tex`, nothing else.
- `--latex-chapter` — `main.tex` + `chapters/01.tex … 16.tex` (one file per chapter).
- `--latex-section` — chapters become folders that `\input` one file per section,
  e.g. `chapters/01/01.tex` + `chapters/01/sections/1.tex …`.
- `--latex-subsection` — sections in turn become folders holding one file per
  subsection, e.g. `chapters/01/sections/07/subsections/1.tex`.

A numbered folder `NN/` always contains its own `NN.tex`; a unit only becomes a
folder when it actually has sub-parts to split out (never an empty folder), and
numbers are zero-padded (`01`) only in a directory holding 10+ items, else plain
(`1`). Standalone units (Exercises, Bibliography) get their own file
(`chapters/exercises.tex`, `chapters/bibliography.tex`), except in the monolithic
case where they stay inline. Whatever the layout, **compile `main.tex`** (the
per-chapter files have no preamble of their own).

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

## Forcing a paragraph indent (`|> Indent`)

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

# Add a shared asset to a course

As an example, say we would like to add `mathjax_setup.js` to course `235A`. We would follow these steps

1. `cd` into project root
2. `ln -s ../../shared/mathjax_setup.js 235A/public/mathjax_setup.js`

# Setting Environment

Create a `.env` file at the root of the project

```
COURSE=235A
OFFLINE_MODE=true
MATHJAX_VERSION=3
```

# Running the local server

Serve the default course specified in `.env` with
`npm run dev`. Override the `COURSE` variable specified
in `.env` by prefixing the command with a `COURSE=<dir>`, e.g., `COURSE=235B npm run dev`.

HOST=0.0.0.0 npm run dev to access from mobile on the same network
