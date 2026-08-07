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
(writes `235A/latex/235A.tex`), then convert it to a PDF with `pdflatex file.tex`.

You can also split the source into multiple files, depending on how you want to
modularise:

- `--latex` — one long `235A.tex`.
- `--latex-chapter` — a `main.tex` that `\input`s one file per chapter.
- `--latex-section` — chapters that in turn `\input` one file per section.
- `--latex-subsection` — sections that in turn `\input` one file per subsection.

Standalone units (e.g. Exercises, Bibliography) get their own file too, except in
the monolithic case. For the modular flags, **compile `main.tex`** (not the
per-chapter files, which have no preamble of their own).

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
cd 235A/latex && pdflatex 235A.tex && pdflatex 235A.tex && pdflatex 235A.tex
```

`latexmk -pdf 235A.tex` does the reruns for you automatically (install it with
`tlmgr install latexmk` if it isn't already available).

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
