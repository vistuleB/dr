import desugaring/core as infra
import desugaring/desugarers as dl
import desugaring/pipelines as pp
import gleam/list
import gleam/string

const minimum_line_wrap_length = 40

const p_cannot_contain = [
  "Algorithm",
  "Bibliography",
  "Carousel",
  "CarouselItems",
  "CarouselItem",
  "Chapter",
  "ChapterTitle",
  "Exercises",
  "Definition",
  "Demo",
  "Example",
  "Exercise",
  "Highlight",
  "Lemma",
  "MathBlock",
  "Observation",
  "Proposition",
  "Proof",
  "Remark",
  "Statement",
  "Section",
  "SectionTitle",
  "SubSection",
  "SubSectionTitle",
  "SubtopicAnnouncement",
  "Theorem",
  "TopicAnnouncement",
  "WriterlyBlankLine",
  "WriterlyCodeBlock",
  "WriterlyComment",
  "br",
  "colgroup",
  "thead",
  "tbody",
  "tr",
  "td",
  "section",
  "Index",
  "center",
  "li",
  "ul",
  "ol",
  "h1",
  "h2",
  "h3",
  "pre",
  "div",
  "hr",
  "figure",
  "img",
  "table",
]

const p_cannot_be_contained_in = [
  "code",
  "p",
  "pre",
  "h1",
  "h2",
  "h3",
  "span",
  "Carousel",
  "ChapterTitle",
  "SectionTitle",
  "SubSectionTitle",
  "Math",
  "MathBlock",
  "Menu",
  "NoWrap",
  "Index",
  "QED",
  "SubtopicAnnouncement",
  "TopicAnnouncement",
  "WriterlyComment",
]

fn ends_with_dollar_starts_with_punctuation(s1: String, s2: String) {
  string.ends_with(s1, "$")
  && {
    string.starts_with(s2, ".")
    || string.starts_with(s2, ",")
    || string.starts_with(s2, ":")
    || string.starts_with(s2, ";")
  }
}

// ┌──────────────────────────────────────────────────────────────────────────┐
// │ Display-math delimiter `$$` policy                                         │
// └──────────────────────────────────────────────────────────────────────────┘
//
// One row per standalone display environment the formatter recognizes, each
// paired with a boolean:  True = wrap the block in `$$`,  False = leave it bare.
// Authors: flip a boolean to change how that environment is normalized.
//
// Any row may be set to False (bare): the HTML renderer (src/pipeline.gleam)
// recognizes exactly this set — it reuses recognized_display_delimiters() — and
// always wraps a bare display environment back in `$$` before MathJax sees it,
// so a bare `\begin{env}` in source still renders correctly. Whether it appears
// bare or `$$`-wrapped in the SOURCE is purely the formatter's cosmetic choice.
fn display_delimiter_dollar_policy() -> List(#(infra.LatexDelimiterPair, Bool)) {
  [
    #(infra.BeginEndAlign, False),
    #(infra.BeginEndAlignStar, False),
    #(infra.BeginEndEnvironment("equation"), True),
    #(infra.BeginEndEnvironment("equation*"), True),
    #(infra.BeginEndEnvironment("alignat"), True),
    #(infra.BeginEndEnvironment("alignat*"), True),
    #(infra.BeginEndEnvironment("flalign"), True),
    #(infra.BeginEndEnvironment("flalign*"), True),
    #(infra.BeginEndEnvironment("gather"), True),
    #(infra.BeginEndEnvironment("gather*"), True),
    #(infra.BeginEndEnvironment("multline"), True),
    #(infra.BeginEndEnvironment("multline*"), True),
    #(infra.BeginEndEnvironment("eqnarray"), True),
    #(infra.BeginEndEnvironment("eqnarray*"), True),
  ]
}

// every standalone display environment in the policy (regardless of its `$$`
// flag). Both the formatter and the HTML renderer (src/pipeline.gleam) feed this
// to create_mathblock_elements, so a bare occurrence is always captured as math
// rather than prose — the invariant that lets any environment be emitted bare.
pub fn recognized_display_delimiters() -> List(infra.LatexDelimiterPair) {
  display_delimiter_dollar_policy() |> list.map(fn(row) { row.0 })
}

// the `\begin{…}` opening token of each environment flagged bare (policy False);
// a MathBlock whose text contains one of these gets its `$$` wrapper stripped
fn bare_display_openings() -> List(String) {
  display_delimiter_dollar_policy()
  |> list.filter(fn(row) { !row.1 })
  |> list.map(fn(row) { { infra.opening_and_closing_string_for_pair(row.0) }.0 })
}

pub fn formatter_pipeline(
  line_length: Int,
  indentation_line_length_penalty: Int,
  // amount subtracted from the line_length at each new level of indentation (with Section, Chapter)
) -> List(infra.Desugarer) {
  [
    [
      dl.identity(),
      dl.attribute_drop_prefixes(#("src", ["./", "/"])),
      dl.delete("QED"),
    ],
    pp.create_mathblock_elements(
      // recognize every standalone display delimiter (see
      // display_delimiter_dollar_policy) as a MathBlock, so a bare (un-`$$`-
      // wrapped) environment like `\begin{equation}` or `\begin{gather}` is
      // captured as math instead of being line-wrapped as prose (which silently
      // corrupts it).
      list.flatten([
        [infra.DoubleDollar, infra.BackslashSquareBracket],
        recognized_display_delimiters(),
      ]),
      infra.DoubleDollar,
      ["WriterlyBlankLine"],
    ),
    [
      dl.concatenate_consecutive_lines_if(
        ends_with_dollar_starts_with_punctuation,
      ),
    ],
    pp.create_math_elements(
      [infra.BackslashParenthesis, infra.SingleDollar],
      infra.SingleDollar,
      infra.BackslashParenthesis,
      ["WriterlyBlankLine"],
    ),
    [
      dl.trim_spaces_around_newlines__outside([
        "pre",
        "Math",
        "MathBlock",
        "WriterlyCodeBlock",
        "WriterlyComment",
      ]),
      dl.trim_ending_spaces_except_last_line(),
      // strip the `$$` wrapper off every MathBlock flagged bare in the policy.
      // Matching is by the exact `\begin{env}` opening token (which carries its
      // closing brace), so `\begin{align}` does NOT match `\begin{alignat}` or
      // the subsidiary `\begin{aligned}` — those keep their `$$`.
      dl.strip_delimiters_inside_if(
        #("MathBlock", infra.latex_strippable_display_delimiters(), fn(vxml) {
          list.any(bare_display_openings(), fn(opening) {
            infra.descendant_text_contains(vxml, opening)
          })
        }),
      ),
      dl.trim_empty_lines("MathBlock"),
      dl.group_consecutive_children__outside(
        #("p", p_cannot_contain),
        p_cannot_be_contained_in,
      ),
      dl.concatenate_text_nodes(),
      dl.insert_text_start_end(#("tt", #("`", "`"))),
      dl.fold_contents_into_text("tt"),
      dl.insert_text_start_end(#("code", #("`", "`"))),
      dl.fold_contents_into_text("code"),
      dl.insert_text_start_end_if_unique_attr(#(
        "span",
        "style",
        "font-variant:small-caps;",
        #("`", "`{sc}"),
      )),
      dl.fold_children_into_text_if(
        #("span", infra.v_has_key_val(_, "style", "font-variant:small-caps;")),
      ),
      dl.wrap_adjacent_non_whitespace_text_with(#(["Math"], "NoWrap")),
      dl.line_rewrap_no2__outside(
        #(
          ["Chapter", "Section", "SubSection"],
          line_length,
          minimum_line_wrap_length,
          indentation_line_length_penalty,
          infra.is_v_and_tag_is_one_of(_, ["Math", "NoWrap"]),
        ),
        ["MathBlock", "pre", "WriterlyCodeBlock", "WriterlyComment"],
      ),
      dl.concatenate_text_nodes(),
      dl.unwrap("NoWrap"),
      dl.last_to_first_concatenate_text_nodes(),
      dl.fold_contents_into_text("Math"),
      dl.delete_empty_lines(),
      dl.split_first_line_after_prefix(#("MathBlock", "\\begin{align}")),
      dl.split_first_line_after_prefix(#("MathBlock", "\\begin{align*}")),
      dl.split_last_line_before_suffix(#("MathBlock", "\\end{align}")),
      dl.split_last_line_before_suffix(#("MathBlock", "\\end{align*}")),
      dl.absorb_forward_one(#("WriterlyComment", "WriterlyBlankLine")),
      dl.absorb_backward_one(#("WriterlyComment", "WriterlyBlankLine")),
      dl.unwrap__outside("WriterlyBlankLine", ["WriterlyComment"]),
      dl.trim_spaces_around_newlines__outside([
        "pre",
        "Math",
        "MathBlock",
        "WriterlyCodeBlock",
        "WriterlyComment",
      ]),
      dl.trim("p"),
      dl.delete_if_empty("p"),
      dl.add_between(#("p", "p", "WriterlyBlankLine")),
      dl.add_between(#("WriterlyCodeBlock", "p", "WriterlyBlankLine")),
      dl.add_before(#("WriterlyCodeBlock", "WriterlyBlankLine")),
      dl.add_between(#("MathBlock", "p", "WriterlyBlankLine")),
      dl.add_between(#("TopicAnnouncement", "p", "WriterlyBlankLine")),
      dl.add_between(#("SubtopicAnnouncement", "p", "WriterlyBlankLine")),
      dl.add_between(#("Exercise", "p", "WriterlyBlankLine")),
      dl.add_between(#("Remark", "p", "WriterlyBlankLine")),
      dl.add_between(#("Theorem", "p", "WriterlyBlankLine")),
      dl.add_between(#("Proof", "p", "WriterlyBlankLine")),
      dl.add_between(#("Definition", "p", "WriterlyBlankLine")),
      dl.add_between(#("Observation", "p", "WriterlyBlankLine")),
      dl.add_between(#("Example", "p", "WriterlyBlankLine")),
      dl.add_between(#("Lemma", "p", "WriterlyBlankLine")),
      dl.add_between(#("Claim", "p", "WriterlyBlankLine")),
      dl.add_between(#("Problem", "p", "WriterlyBlankLine")),
      dl.add_between(#("Algorithm", "p", "WriterlyBlankLine")),
      dl.add_between(#("Demo", "p", "WriterlyBlankLine")),
      dl.add_between(#("Statement", "p", "WriterlyBlankLine")),
      dl.add_between(#("h3", "p", "WriterlyBlankLine")),
      dl.add_between(#("h2", "p", "WriterlyBlankLine")),
      dl.add_between(#("ol", "p", "WriterlyBlankLine")),
      dl.add_between(#("ul", "p", "WriterlyBlankLine")),
      dl.add_between(#("figure", "p", "WriterlyBlankLine")),
      dl.add_between(#("Carousel", "p", "WriterlyBlankLine")),
      dl.add_between(#("pre", "p", "WriterlyBlankLine")),
      dl.add_between(#("div", "p", "WriterlyBlankLine")),
      dl.add_between(#("Highlight", "p", "WriterlyBlankLine")),
      dl.expel_initial_last_backward_forward(
        #("WriterlyComment", ["WriterlyBlankLine"], ["WriterlyBlankLine"]),
      ),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "MathBlock",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "TopicAnnouncement",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "SubtopicAnnouncement",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Exercise",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Remark",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Theorem",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Proof",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Definition",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Observation",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Example",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Lemma",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Claim",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Problem",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Algorithm",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Demo",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Statement",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "h3",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "h2",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "ol",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "ul",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "li",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "figure",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Carousel",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "pre",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "div",
        "WriterlyBlankLine",
      )),
      dl.add_if_missing_before_but_not_before_first_child(#(
        "Highlight",
        "WriterlyBlankLine",
      )),
      dl.prepend(#("Chapter", "WriterlyBlankLine")),
      dl.prepend(#("Section", "WriterlyBlankLine")),
      dl.prepend(#("SubSection", "WriterlyBlankLine")),
      dl.unwrap("p"),
      dl.unwrap("MathBlock"),
      dl.delete_attribute__batch(["test", "t"]),
      dl.format_writerly_commented_attributes(),
    ],
  ]
  |> list.flatten
}
