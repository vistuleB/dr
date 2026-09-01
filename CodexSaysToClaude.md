# Audit of the `dr` Gleam Sources

The audit found several concrete bugs and performance problems, plus two large
structural cleanup opportunities. No Gleam files were changed during the audit.
`gleam check` passes.

## Likely bugs

### 1. `--which` accepts a non-directory

In `src/main.gleam`, the result of `simplifile.is_directory` is matched as
`Ok(_)`, so both `Ok(True)` and `Ok(False)` are accepted:

```gleam
case simplifile.is_directory(name <> "/wly") {
  Ok(_) -> on.Stay(name)
```

This should match only `Ok(True)`.

### 2. Formatter cleanup probably does nothing

`src/formatter_renderer.gleam` contains:

```gleam
let _ = simplifile.delete(parameters.output_dir <> "/*")
```

`simplifile.delete` receives a literal path; it does not perform shell glob
expansion. The result is also discarded. Existing output files are therefore
probably not being deleted.

### 3. Duplicate standalone sections are silently discarded

`src/renderer.gleam` says Exercises and Bibliography may occur "at most one,"
but patterns such as:

```gleam
[exercises, ..] -> [...]
```

silently use the first and ignore the rest. Duplicate instances should produce
a splitter error.

### 4. Extra formatter arguments are silently ignored

`src/formatter_renderer.gleam` accepts `[second, ..]`, discarding everything
following the indentation penalty. A malformed command such as
`--fmt 80 2 nonsense` therefore succeeds.

### 5. User-input failures become runtime panics

`src/renderer.gleam` asserts that Writerly parsing succeeded, then uses `panic`
for missing document metadata. `src/latex_renderer.gleam` similarly asserts
parser success.

Malformed source and missing required metadata are document errors, not
unreachable programmer states. They should become ordinary renderer errors.

## Performance problems

### 6. Quadratic LaTeX string construction

`nodes_to_latex` in `src/latex_renderer.gleam` repeatedly appends to an
expanding immutable string:

```gleam
#(in_para, hint, out <> chunk)
```

The same pattern appears in `hier_children` and `hier_document`. Large courses
can make these operations quadratic in generated output size.
`gleam/string_tree`, reversed chunk accumulation, or a final `string.concat`
would avoid that.

### 7. Quadratic list construction

The same LaTeX functions repeatedly call `list.append(files, new_files)` on
growing accumulators.

`whole_book_splitter` in `src/formatter_renderer.gleam` also repeatedly appends
sections and subsections during nested folds. Accumulating in reverse and
reversing once would be linear.

That formatter fold additionally reverses chapters through prepending while
preserving section and subsection order through appending. The resulting
ordering policy is inconsistent and should be tested.

### 8. Artifact comparisons use repeated linear membership searches

Both `src/renderer.gleam` and `src/latex_renderer.gleam` compare file lists
using `list.contains` inside `list.filter`, making the comparison quadratic.
Converting one side to a `gleam/set` would be clearer and faster.

### 9. Regular expressions are compiled repeatedly

`style_width_fraction` in `src/latex_renderer.gleam` compiles its width regex
for every matching image. `collapse_blank_lines` recompiles its regex for every
emitted file.

They could be compiled once per render and stored in the LaTeX context.

## Structural cleanup

### 10. Five HTML emitters duplicate almost the entire page shell

`src/renderer.gleam` contains separate index, chapter, section, subsection, and
standalone emitters. They repeat the doctype, `<head>`, metadata, stylesheets,
MathJax, scripts, body, and footer.

One shared `html_page_lines` helper could take the title, body attributes,
content, and blame label. This would remove several hundred lines and prevent
variants from drifting apart.

### 11. Document metadata extraction is repetitive

`src/renderer.gleam` repeats lookup, panic, binding, and printing for every
field. A `required_document_attribute` helper plus a `DocumentInfo` constructor
would shorten this and provide consistent errors.

The HTML and LaTeX renderers also independently parse `__parent.wly` and
construct similar `DocumentInfo` values. A shared `document_info.gleam` module
appears justified.

### 12. `latex_renderer.gleam` has too many responsibilities

At approximately 1,434 lines, it combines:

- escaping and tokenization;
- VXML-to-LaTeX conversion;
- hierarchical file splitting;
- filesystem cleanup and figure copying;
- renderer orchestration.

A natural division would be `latex/escaping.gleam`, `latex/emitter.gleam`,
`latex/splitter.gleam`, and the existing renderer entry point. This would also
make focused tests easier.

## Error handling and testing

`fragment_bundler` in `src/formatter_renderer.gleam` asserts that every
fragment is a V-node with `Src` blame and otherwise produces an unlabelled
panic. Since its enclosing splitters already return `Result(..., String)`, it
could return a descriptive splitter error.

The renderer and LaTeX machinery have little direct test coverage despite
containing most of the project-specific complexity. The highest-value tests
would cover:

- `--which` directory validation;
- formatter option parsing and rejection of excess arguments;
- formatter fragment ordering;
- duplicate Exercises/Bibliography rejection;
- LaTeX escaping and paragraph handling;
- modular LaTeX filenames and `\input` ordering;
- the shared HTML page shell after extraction.

The first implementation pass should address findings 1–7 before reorganizing
modules.
