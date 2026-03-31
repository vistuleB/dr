import desugarer_library as dl
import gleam/list
import infrastructure.{type Pipe} as infra

pub fn pipeline() -> List(Pipe) {
  let pre_transformation_document_tags = [
    "Chapter",
    "ChapterTitle",
    "Document",
    "footnote",
    "Labeled",
    "Section",
    "SubTitle",
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
    dl.check_tags(#(pre_transformation_approved_tags, "pre-transformation")),
    dl.auto_generate_child_if_missing_from_attribute(#(
      "Chapter",
      "ChapterTitle",
      "title",
    )),
    dl.auto_generate_child_if_missing_from_attribute(#(
      "Section",
      "SubTitle",
      "title",
    )),

    dl.dr_create_index(),
    dl.append_class__batch([
      #("Index", "index"),
      #("Chapter", "chapter"),
      #("Section", "subchapter"),
    ]),
    dl.rename__batch([
      #("Index", "div"),
      #("Chapter", "div"),
      #("ChapterTitle", "div"),
      #("footnote", "div"),
      #("Labeled", "div"),
      #("Section", "div"),
      #("SubTitle", "div"),
    ]),
    dl.check_tags(#(post_transformation_approved_tags, "post-transformation")),
  ]
  |> infra.desugarers_2_pipeline
}
