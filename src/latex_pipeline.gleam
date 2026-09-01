import formatter_pipeline
import gleam/list
import gleam/string
import vxml_pipeline/core as infra
import vxml_pipeline/delimited_syntax as syntax
import vxml_pipeline/desugarers as dl
import vxml_pipeline/split_replacement as sr
import writerly

// The prose words that introduce a numbered cross-reference. A "<word> >>handle"
// span becomes a single `AutoRef` node so the emitter can hyperlink the whole
// "Theorem 3.14" (name + number), not just the number. Add to this list to
// cover more reference words. Shared with the emitter (`latex_renderer`), which
// applies the same recognition to attribute-borne refs like a Proof's
// `alt-title` (which never becomes a text node, so the pipeline can't reach it).
pub const autoref_words = [
  "Theorem", "Lemma", "Proposition", "Corollary", "Definition", "Example",
  "Exercise",
]

// Splitter that matches `\b(<word>|<word>|…) >>handle` in a text node and turns
// the match into `V("AutoRef", ref="<word> >>handle")` (one capture group over
// the whole span). Handle charset matches the emitter's ref token
// (letter, then letters/digits/`_`/`:`/`-`); `.` is excluded on purpose.
fn autoref_named_links_split_rule() -> sr.RegexpSplitRule {
  let words = string.join(autoref_words, "|")
  sr.regexp_split_rule_for_groups([
    #(
      "\\b(?:" <> words <> ")\\s+>>[A-Za-z][A-Za-z0-9_:-]*",
      sr.TagWithSegmentAsValue("AutoRef", "ref"),
    ),
  ])
}

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
      dl.delete_attribute_if(fn(key, _) {
        writerly.is_commented_attribute_key(key)
      }),
      dl.unwrap_if_first_child("WriterlyBlankLine"),
    ],
    // Recognize every standalone display environment (plus `$$`) as a
    // MathBlock, so the emitter can strip the `$$` and emit the environment
    // (or `\[ ... \]`) directly. Shares the recognition set with the formatter.
    syntax.create_mathblock_elements(
      list.flatten([
        [infra.DoubleDollar],
        formatter_pipeline.recognized_display_delimiters(),
      ]),
      infra.DoubleDollar,
      ["WriterlyBlankLine", "Indent"],
    ),
    // `[text](url)` -> `a` node (emitter -> `\href`). Must precede inline math.
    syntax.markdown_link_pipeline(["WriterlyBlankLine", "Indent"], ["MathBlock"]),
    // `$...$` / `\(...\)` -> Math node (emitted verbatim, protected from the
    // emphasis splitting and prose-escaping that follow).
    syntax.create_math_elements(
      [infra.BackslashParenthesis, infra.SingleDollar],
      infra.SingleDollar,
      infra.BackslashParenthesis,
      ["WriterlyBlankLine", "Indent"],
    ),
    // Named cross-references: recognize "Theorem >>handle" / "Lemma >>handle" /
    // … in prose and pull the whole "<word> >>handle" span into a single
    // `AutoRef` node (`ref` attr), so the emitter can hyperlink the WHOLE
    // "Theorem 3.14" (not just the number). Runs BEFORE the emphasis splitters
    // so a handle containing `_` is safely inside an attribute by then; stays
    // out of Math/MathBlock (refs there are equation refs) and `a` (link text).
    [
      dl.regex_split_and_replace__outside(autoref_named_links_split_rule(), [
        "Math",
        "MathBlock",
        "a",
      ]),
    ],
    // `_italic_` -> <i> (emitter -> \emph), `*bold*` -> <b> (emitter -> \textbf),
    // skipping anything inside math.
    syntax.permissive_symmetric_delimiter_pipeline(
      "_",
      "_",
      "i",
      ["WriterlyBlankLine", "Indent"],
      [
        "MathBlock",
        "Math",
      ],
    ),
    syntax.permissive_symmetric_delimiter_pipeline(
      "\\*",
      "*",
      "b",
      ["WriterlyBlankLine", "Indent"],
      [
        "MathBlock",
        "Math",
      ],
    ),
    [
      // Must run after the splitting steps: turns a literal `\_` / `\*` back
      // into a bare `_` / `*` outside math. The emitter's prose escaper then
      // re-escapes `_` -> `\_` (a literal underscore in LaTeX text).
      dl.unescape_delimiters__outside(["_", "*"], ["Math", "MathBlock"]),
    ],
  ]
  |> list.flatten
}
