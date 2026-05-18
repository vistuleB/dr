import blame as bl
import desugarer_library as dl
import gleam/list
import gleam/string
import infrastructure as infra
import prefabricated_pipelines as pp
import vxml

const our_blame = bl.Des([], "pipeline", 8)

const p_cannot_contain = [
  "Chapter",
  "ChapterTitle",
  "Labeled",
  "MathBlock",
  "Proof",
  "Section",
  "SectionTitle",
  "Statement",
  "SubSection",
  "SubSectionTitle",
  "WriterlyBlankLine",
  "li",
  "ol",
  "h1",
  "h3",
  "p",
  "ul",
]

const p_cannot_be_contained_in = [
  "ChapterTitle",
  "SectionTitle",
  "SubSectionTitle",
  "Math",
  "MathBlock",
  "h1",
  "h3",
  "p",
]

pub fn pipeline() -> List(infra.Desugarer) {
  let pre_transformation_document_tags = [
    "Chapter",
    "ChapterTitle",
    "Definition",
    "Document",
    "Example",
    "Labeled",
    "Lemma",
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
    "h3",
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

  let proof_span =
    vxml.V(our_blame, "span", [vxml.Attr(our_blame, "class", "proof")], [])

  let proof_default =
    vxml.V(our_blame, "span", [vxml.Attr(our_blame, "class", "proof")], [
      vxml.T(our_blame, [vxml.Line(our_blame, "Proof.")]),
    ])

  [
    [
      dl.check_tags(#(pre_transformation_approved_tags, "pre-transformation")),
      dl.delete("WriterlyComment"),
      dl.delete_attribute_if(fn(key, _) { string.starts_with(key, "!!") }),
      dl.unwrap_if_first_child("WriterlyBlankLine"),
      dl.append(#("Proof", "QED", infra.Continue)),
      dl.replace_with_arbitrary(#("QED", qed)),
      dl.prepend_attribute_as_first_line(#("Definition", "label")),
      dl.prepend_attribute_as_first_line(#("Theorem", "label")),
      dl.rename_with_attributes__batch([
        #("Definition", "Statement", [
          #("title", "*Definition*"),
          #("class", "statement definition"),
        ]),
        #("Example", "Statement", [
          #("title", "*Example*"),
          #("class", "statement"),
        ]),
        #("Lemma", "Statement", [
          #("title", "*Lemma*"),
          #("class", "statement"),
        ]),
        #("Theorem", "Statement", [
          #("title", "*Theorem*"),
          #("class", "statement"),
        ]),
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
        #("Statement", "*::øøChapterCounter.::øøStatementCounter*" <> " "),
      ]),
      dl.insert_attribute_as_text(#("Statement", "title")),
      dl.wrap_if_first_child_of(#("Statement", "h3")),
      dl.prepend_attribute_as_wrapped_text_else_custom(#(
        "Proof",
        "alt-title",
        proof_span,
        proof_default,
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
      dl.find_replace_if_has_ancestor_else(
        #(["Math", "MathBlock"], #("``", "“"), #("``", "\"")),
      ),
      dl.find_replace_if_has_ancestor_else(
        #(["Math", "MathBlock"], #("''", "”"), #("''", "\"")),
      ),
      dl.group_consecutive_children__outside(
        #("p", p_cannot_contain),
        p_cannot_be_contained_in,
      ),
      dl.unwrap("WriterlyBlankLine"),
      dl.trim("p"),
      dl.delete_if_empty("p"),
      dl.append_class__batch([
        #("MathBlock", "math-block"),
      ]),
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
        #("Proof", "div"),
        #("Section", "div"),
        #("SectionTitle", "h1"),
        #("Statement", "div"),
        #("SubSection", "div"),
        #("SubSectionTitle", "h1"),
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
}
