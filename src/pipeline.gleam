import desugarer_library as dl
import gleam/list
import infrastructure.{type Pipe} as infra
import prefabricated_pipelines as pp

const p_cannot_contain = [
  "Chapter",
  "ChapterTitle",
  "Labeled",
  "MathBlock",
  "Section",
  "SectionTitle",
  "SubSection",
  "SubSectionTitle",
  "WriterlyBlankLine",
  "li",
  "ol",
  "p",
  "ul",
]

const p_cannot_be_contained_in = [
  "ChapterTitle",
  "SectionTitle",
  "SubSectionTitle",
  "Math",
  "MathBlock",
  "p",
]

pub fn pipeline() -> List(Pipe) {
  let pre_transformation_document_tags = [
    "Chapter",
    "ChapterTitle",
    "Document",
    "Labeled",
    "Section",
    "SectionTitle",
    "SubSection",
    "SubSectionTitle",
    "WriterlyBlankLine",
    "footnote",
  ]

  let pre_transformation_html_tags = ["li", "ol", "ul"]
  let pre_transformation_approved_tags =
    [pre_transformation_document_tags, pre_transformation_html_tags]
    |> list.flatten

  let post_transformation_document_tags = ["Document", "WriterlyBlankLine"]
  let post_transformation_html_tags = [
    "a",
    "b",
    "br",
    "div",
    "h1",
    "header",
    "i",
    "li",
    "ol",
    "p",
    "ul",
  ]
  let post_transformation_approved_tags =
    [post_transformation_document_tags, post_transformation_html_tags]
    |> list.flatten

  [
    [
      dl.check_tags(#(pre_transformation_approved_tags, "pre-transformation")),
      dl.auto_generate_child_if_missing_from_attribute(#(
        "Chapter",
        "ChapterTitle",
        "title",
      )),
      dl.auto_generate_child_if_missing_from_attribute(#(
        "Section",
        "SectionTitle",
        "title",
      )),
      dl.auto_generate_child_if_missing_from_attribute(#(
        "SubSection",
        "SubSectionTitle",
        "title",
      )),
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
    pp.barbaric_symmetric_delim_splitting("_", "_", "i", [
      "MathBlock",
      "Math",
    ]),
    pp.barbaric_symmetric_delim_splitting("\\*", "*", "b", [
      "MathBlock",
      "Math",
    ]),
    [
      dl.fold_contents_into_text("Math"),
      dl.group_consecutive_children__outside(
        #("p", p_cannot_contain),
        p_cannot_be_contained_in,
      ),
      dl.unwrap("WriterlyBlankLine"),
      dl.trim("p"),
      dl.delete_if_empty("p"),
      dl.dr_create_index(),
      dl.append_class__batch([
        #("Index", "index"),
        #("Chapter", "chapter"),
        #("Section", "section"),
        #("SubSection", "subsection"),
      ]),
      dl.rename__batch([
        #("Chapter", "div"),
        #("ChapterTitle", "h1"),
        #("Index", "div"),
        #("Labeled", "div"),
        #("MathBlock", "div"),
        #("Section", "div"),
        #("SectionTitle", "h1"),
        #("SubSection", "div"),
        #("SubSectionTitle", "h1"),
        #("footnote", "div"),
      ]),
      dl.check_tags(#(post_transformation_approved_tags, "post-transformation")),
    ],
  ]
  |> list.flatten
  |> infra.desugarers_2_pipeline
}
