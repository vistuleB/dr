import desugaring/core as infra
import desugaring/desugarers as dl
import desugaring/pipelines as pp
import formatter_pipeline
import gleam/list
import gleam/string

// The wly -> LaTeX pipeline.
//
// Unlike the HTML pipeline (`pipeline.gleam`), this one keeps the *semantic*
// tags (`Chapter`, `Section`, `Definition`, `Theorem`, `Proof`, `MathBlock`,
// `Math`, `ol`, `li`, ...) all the way to the emitter, which maps them onto
// idiomatic LaTeX constructs (`\chapter`, `\section`, `\newtheorem`
// environments, `proof`, `\[ ... \]`, `enumerate`, ...). LaTeX/hyperref then
// number everything and build the clickable TOC + PDF outline.
//
// We therefore deliberately DO NOT run any of the HTML-only machinery:
// counter baking, `handles_*` link substitution, `dr_create_index`,
// `dr_create_menu`, smart-quote replacement (`` `` `` / `''` are already valid
// LaTeX quotes) or the final rename-to-HTML batch. The only transformations we
// keep are the ones that turn Writerly's inline syntax into a shape the emitter
// can walk verbatim.
pub fn latex_pipeline() -> List(infra.Desugarer) {
  [
    [
      dl.delete("WriterlyComment"),
      dl.delete_attribute_if(fn(key, _) { string.starts_with(key, "!!") }),
      dl.unwrap_if_first_child("WriterlyBlankLine"),
    ],
    // Recognize every standalone display environment (plus `$$`) as a
    // MathBlock, so the emitter can strip the `$$` and emit the environment
    // (or `\[ ... \]`) directly. Shares the recognition set with the formatter.
    pp.create_mathblock_elements(
      list.flatten([
        [infra.DoubleDollar],
        formatter_pipeline.recognized_display_delimiters(),
      ]),
      infra.DoubleDollar,
      ["WriterlyBlankLine"],
    ),
    // `[text](url)` -> `a` node (emitter -> `\href`). Must precede inline math.
    pp.markdown_link_splitting(["WriterlyBlankLine"], ["MathBlock"]),
    // `$...$` / `\(...\)` -> Math node (emitted verbatim, protected from the
    // emphasis splitting and prose-escaping that follow).
    pp.create_math_elements(
      [infra.BackslashParenthesis, infra.SingleDollar],
      infra.SingleDollar,
      infra.BackslashParenthesis,
      ["WriterlyBlankLine"],
    ),
    // `_italic_` -> <i> (emitter -> \emph), `*bold*` -> <b> (emitter -> \textbf),
    // skipping anything inside math.
    pp.barbaric_symmetric_delim_splitting("_", "_", "i", ["WriterlyBlankLine"], [
      "MathBlock",
      "Math",
    ]),
    pp.barbaric_symmetric_delim_splitting("\\*", "*", "b", ["WriterlyBlankLine"], [
      "MathBlock",
      "Math",
    ]),
    [
      // Must run after the splitting steps: turns a literal `\_` / `\*` back
      // into a bare `_` / `*` outside math. The emitter's prose escaper then
      // re-escapes `_` -> `\_` (a literal underscore in LaTeX text).
      dl.unescape_delimiters__outside(["_", "*"], ["Math", "MathBlock"]),
    ],
  ]
  |> list.flatten
}
