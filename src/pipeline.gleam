import desugarer_library as dl
import gleam/list
import gleam/string
import group_replacement_splitting as grs
import infrastructure.{type Pipe} as infra
import prefabricated_pipelines as pp

const p_cannot_contain = [
  "CentralDisplay",
  "CentralDisplayItalic",
  "Chapter",
  "ChapterTitle",
  "Index",
  "MathBlock",
  "Sub",
  "SubTitle",
  "WriterlyBlankLine",
  "br",
  "center",
  "colgroup",
  "figure",
  "div",
  "hr",
  "li",
  "ol",
  "p",
  "pre",
  "section",
  "table",
  "thead",
  "tbody",
  "tr",
  "td",
  "ul",
]

const p_cannot_be_contained_in = [
  "Index",
  "Math",
  "MathBlock",
  "figure",
  "p",
  "pre",
  "span",
]

pub fn pipeline(author_mode: Bool) -> List(Pipe) {
  let escaped_dollar_to_span_rr_splitter =
    grs.rr_splitter_for_groups([
      #("\\\\", grs.Trash),
      #("\\$", grs.TagWithTextChild("span")),
    ])

  let pre_transformation_document_tags = [
    "Chapter",
    "ChapterTitle",
    "Document",
    "MathBlock",
    "Sub",
    "SubTitle",
    "WriterlyBlankLine",
    "WriterlyComment",
  ]

  let pre_transformation_html_tags = [
    "div",
    "a",
    "pre",
    "span",
    "br",
    "hr",
    "img",
    "figure",
    "figcaption",
    "ol",
    "ul",
    "li",
  ]
  let pre_transformation_approved_tags =
    [pre_transformation_document_tags, pre_transformation_html_tags]
    |> list.flatten

  let post_transformation_document_tags = ["Document"]
  let post_transformation_html_tags =
    pre_transformation_html_tags
    |> list.append([
      "header",
      "nav",
      "section",
      "h1",
      "h2",
      "h3",
      "p",
      "b",
      "i",
    ])
  let post_transformation_approved_tags =
    [post_transformation_document_tags, post_transformation_html_tags]
    |> list.flatten

  [
    [
      dl.check_tags(#(pre_transformation_approved_tags, "pre-transformation")),
      dl.delete("WriterlyComment"),
      dl.delete_attribute_if(fn(key, _) { string.starts_with(key, "!!") }),
      dl.append_attribute__batch([
        #("Document", "counter", "ChapterCounter"),
        #("Chapter", "counter", "SubCounter"),
      ]),
      dl.prepend_attribute(#(
        "Chapter",
        "path",
        "./::øøChapterCounter-0.html",
        infra.GoBack,
      )),
      dl.prepend_attribute(#(
        "Sub",
        "path",
        "./::øøChapterCounter-::øøSubCounter.html",
        infra.GoBack,
      )),
      dl.prepend_counter_incrementing_attribute(#(
        "Chapter",
        "ChapterCounter",
        infra.GoBack,
      )),
      dl.prepend_counter_incrementing_attribute(#(
        "Sub",
        "SubCounter",
        infra.GoBack,
      )),
      dl.set_handle_value(#("Chapter", "::øøChapterCounter", infra.GoBack)),
      dl.set_handle_value(#(
        "Sub",
        "::øøChapterCounter.::øøSubCounter",
        infra.GoBack,
      )),
      dl.auto_generate_child_if_missing_from_attribute(#(
        "Chapter",
        "ChapterTitle",
        "title",
      )),
      dl.auto_generate_child_if_missing_from_attribute(#(
        "Sub",
        "SubTitle",
        "title",
      )),
      dl.prepend_attribute(#(
        "ChapterTitle",
        "number-chiron",
        "::øøChapterCounter.",
        infra.GoBack,
      )),
      dl.prepend_attribute(#(
        "SubTitle",
        "number-chiron",
        "::øøChapterCounter.::øøSubCounter",
        infra.GoBack,
      )),
      dl.substitute_counters(),
    ],
    pp.create_mathblock_elements(
      [infra.DoubleDollar, infra.BeginEndAlign, infra.BeginEndAlignStar],
      infra.DoubleDollar,
    ),
    pp.create_math_elements(
      [infra.BackslashParenthesis, infra.SingleDollar],
      infra.SingleDollar,
      infra.BackslashParenthesis,
    ),
    [
      dl.regex_split_and_replace__outside(escaped_dollar_to_span_rr_splitter, [
        "Math",
        "MathBlock",
      ]),
      dl.group_consecutive_children__outside(
        #("p", p_cannot_contain),
        p_cannot_be_contained_in,
      ),
      dl.unwrap("WriterlyBlankLine"),
      dl.trim("p"),
      dl.delete_if_empty("p"),
      dl.ti2_create_index(),
      dl.insert_attribute_value_at_first_child_start(#(
        "ChapterTitle",
        "number-chiron",
        "&ensp;",
        infra.GoBack,
      )),
      dl.insert_attribute_value_at_first_child_start(#(
        "SubTitle",
        "number-chiron",
        "&ensp;",
        infra.GoBack,
      )),
    ],
    [
      dl.append_class__batch([
        #("Index", "index"),
        #("Chapter", "chapter"),
        #("ChapterTitle", "main-column page-title"),
        #("Sub", "subchapter"),
        #("MathBlock", "math-block"),
      ]),
    ],
    case author_mode {
      False -> []
      True -> []
    },
    [
      dl.fold_contents_into_text("Math"),
      dl.rename__batch([
        #("MathBlock", "div"),
        #("Index", "div"),
        #("Chapter", "div"),
        #("ChapterTitle", "div"),
        #("Sub", "div"),
        #("SubTitle", "div"),
      ]),
      dl.check_tags(#(post_transformation_approved_tags, "post-transformation")),
    ],
  ]
  |> list.flatten
  |> infra.desugarers_2_pipeline
}
