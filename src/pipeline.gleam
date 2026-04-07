import desugarer_library as dl
import gleam/list
import infrastructure.{type Pipe} as infra
import prefabricated_pipelines as pp

pub fn pipeline() -> List(Pipe) {
  let pre_transformation_document_tags = [
    "Chapter",
    "ChapterTitle",
    "Document",
    "footnote",
    "Labeled",
    "Section",
    "SectionTitle",
    "SubSection",
    "SubSectionTitle",
    "WriterlyBlankLine",
  ]

  let pre_transformation_html_tags = []
  let pre_transformation_approved_tags =
    [pre_transformation_document_tags, pre_transformation_html_tags]
    |> list.flatten

  let post_transformation_document_tags = ["Document", "WriterlyBlankLine"]
  let post_transformation_html_tags = [
    "a",
    "br",
    "div",
    "h1",
    "header",
    "li",
    "ol",
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
    pp.create_math_elements(
      [infra.BackslashParenthesis, infra.SingleDollar],
      infra.SingleDollar,
      infra.BackslashParenthesis,
    ),
    [
      dl.fold_contents_into_text("Math"),
      dl.dr_create_index(),
      dl.append_class__batch([
        #("Index", "index"),
        #("Chapter", "chapter"),
        #("Section", "section"),
        #("SubSection", "subsection"),
      ]),
      dl.rename__batch([
        #("Index", "div"),
        #("Chapter", "div"),
        #("ChapterTitle", "div"),
        #("footnote", "div"),
        #("Labeled", "div"),
        #("Section", "div"),
        #("SectionTitle", "div"),
        #("SubSection", "div"),
        #("SubSectionTitle", "div"),
      ]),
      dl.check_tags(#(post_transformation_approved_tags, "post-transformation")),
    ],
  ]
  |> list.flatten
  |> infra.desugarers_2_pipeline
}
