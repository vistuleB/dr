import blame as bl
import desugarer_library as dl
import gleam/list
import infrastructure.{type Pipe} as infra
import prefabricated_pipelines as pp
import vxml

const our_blame = bl.Des([], "pipeline", 8)

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
    "Example",
    "Labeled",
    "Proof",
    "Section",
    "SectionTitle",
    "SubSection",
    "SubSectionTitle",
    "Theorem",
    "WriterlyBlankLine",
    "footnote",
  ]

  let pre_transformation_html_tags = ["li", "ol", "ul"]
  let pre_transformation_approved_tags =
    [pre_transformation_document_tags, pre_transformation_html_tags]
    |> list.flatten

  let post_transformation_document_tags = ["Document"]
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
    "span",
    "ul",
  ]
  let post_transformation_approved_tags =
    [post_transformation_document_tags, post_transformation_html_tags]
    |> list.flatten
  let qed = [
    vxml.V(
      our_blame,
      "span",
      [vxml.Attr(our_blame, "style", "color:#0000;visibility:none;")],
      [vxml.T(our_blame, [vxml.Line(our_blame, "A")])],
    ),
    vxml.V(our_blame, "span", [vxml.Attr(our_blame, "class", "qed")], [
      vxml.T(our_blame, [vxml.Line(our_blame, "\\(\\square\\)")]),
    ]),
  ]

  [
    [
      dl.check_tags(#(pre_transformation_approved_tags, "pre-transformation")),
      dl.append(#("Proof", "QED", infra.Continue)),
      dl.replace_with_arbitrary(#("QED", qed)),
      dl.rename_with_attributes__batch([
        #("Example", "Statement", [#("title", "*Example*")]),
        #("Theorem", "Statement", [#("title", "*Theorem*")]),
      ]),
      dl.append_attribute__batch([
        #("Document", "counter", "ChapterCounter"),
        #("Chapter", "counter", "SectionCounter"),
        #("Section", "counter", "SubSectionCounter"),
        #("Chapter", "counter", "StatementCounter"),
      ]),
      dl.prepend_counter_incrementing_attribute(#(
        "Chapter",
        "ChapterCounter",
        infra.GoBack,
      )),
      dl.prepend_counter_incrementing_attribute(#(
        "Section",
        "SectionCounter",
        infra.GoBack,
      )),
      dl.prepend_counter_incrementing_attribute(#(
        "SubSection",
        "SubSectionCounter",
        infra.GoBack,
      )),
      dl.prepend_counter_incrementing_attribute(#(
        "Statement",
        "StatementCounter",
        infra.GoBack,
      )),
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
      dl.dr_create_index(),
      dl.prepend_text_node__batch([
        #("ChapterTitle", "::øøChapterCounter. "),
        #("SectionTitle", "::øøChapterCounter.::øøSectionCounter "),
        #(
          "SubSectionTitle",
          "::øøChapterCounter.::øøSectionCounter.::øøSubSectionCounter ",
        ),
        #("Example", "::øøChapterCounter.::øøStatementCounter "),
        #("Theorem", "::øøChapterCounter.::øøStatementCounter "),
        #("Statement", "*::øøChapterCounter.::øøStatementCounter*" <> " "),
      ]),
      dl.insert_attribute_as_text(#("Statement", "title")),
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
      dl.append_class__batch([
        #("Index", "index"),
        #("Chapter", "chapter"),
        #("Section", "section"),
        #("SubSection", "subsection"),
      ]),
      dl.rename__batch([
        #("Chapter", "div"),
        #("ChapterTitle", "h1"),
        #("Example", "div"),
        #("Index", "div"),
        #("Labeled", "div"),
        #("MathBlock", "div"),
        #("Proof", "div"),
        #("Section", "div"),
        #("SectionTitle", "h1"),
        #("Statement", "div"),
        #("SubSection", "div"),
        #("SubSectionTitle", "h1"),
        #("Theorem", "div"),
        #("footnote", "div"),
      ]),
      dl.delete_attribute__batch([
        "_",
        "counter",
        "title",
      ]),
      dl.check_tags(#(post_transformation_approved_tags, "post-transformation")),
    ],
  ]
  |> list.flatten
  |> infra.desugarers_2_pipeline
}
