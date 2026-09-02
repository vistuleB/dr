import formatter_pipeline
import gleam/list
import local_desugarers as local_dl
import vxml
import vxml/blame as bl
import vxml_pipeline as ds
import vxml_pipeline/core as infra
import vxml_pipeline/delimited_syntax as syntax
import vxml_pipeline/desugarers as dl
import writerly

const our_blame = bl.Des([], "pipeline", 8)

const p_cannot_contain = [
  "Bibliography",
  "BibliographyTitle",
  "Indent",
  "Chapter",
  "ChapterTitle",
  "Exercises",
  "ExercisesTitle",
  "Footnote",
  "Labeled",
  "MathBlock",
  "Navigation",
  "Proof",
  "Section",
  "SectionTitle",
  "Statement",
  "SubSection",
  "SubSectionTitle",
  "WriterlyBlankLine",
  "figure",
  "hr",
  "li",
  "ol",
  "h1",
  "h3",
  "p",
  "ul",
]

const p_cannot_be_contained_in = [
  "BibliographyTitle",
  "ChapterTitle",
  "SectionTitle",
  "SubSectionTitle",
  "ExercisesTitle",
  "Math",
  "MathBlock",
  "Navigation",
  "figure",
  "h1",
  "h3",
  "p",
]

pub fn pipeline(
  course: String,
  parameters: ds.RendererParameters,
  author_mode: Bool,
) -> List(infra.Desugarer) {
  let pre_transformation_document_tags = [
    "Bibliography",
    "BibliographyTitle",
    "Indent",
    "Chapter",
    "ChapterTitle",
    "Corollary",
    "Definition",
    "Document",
    "Example",
    "Exercise",
    "Exercises",
    "ExercisesTitle",
    "Labeled",
    "Lemma",
    "Proof",
    "Section",
    "SectionTitle",
    "SubSection",
    "SubSectionTitle",
    "Theorem",
    "WriterlyBlankLine",
    "WriterlyComment",
    "Footnote",
    "hr",
  ]

  let pre_transformation_html_tags = [
    "figcaption",
    "figure",
    "img",
    "li",
    "ol",
    "span",
    "ul",
  ]
  let pre_transformation_approved_tags =
    [pre_transformation_document_tags, pre_transformation_html_tags]
    |> list.flatten

  let post_transformation_document_tags = ["Document"]
  let post_transformation_html_tags = [
    "a",
    "b",
    "br",
    "div",
    "figcaption",
    "figure",
    "h1",
    "h3",
    "header",
    "hr",
    "i",
    "img",
    "li",
    "ol",
    "p",
    "span",
    "sup",
    "ul",
    "InTextWarning",
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
      vxml.T(our_blame, [vxml.Line(our_blame, "$\\square$")]),
    ]),
  ]

  let proof_span =
    vxml.V(our_blame, "span", [vxml.Attr(our_blame, "class", "proof")], [])

  let proof_default =
    vxml.V(our_blame, "span", [vxml.Attr(our_blame, "class", "proof")], [
      vxml.T(our_blame, [vxml.Line(our_blame, "Proof")]),
    ])

  let label_span =
    vxml.V(our_blame, "span", [vxml.Attr(our_blame, "class", "label")], [])

  [
    [
      dl.check_tags(#(pre_transformation_approved_tags, "pre-transformation")),
      dl.delete("WriterlyComment"),
      dl.concatenate_text_nodes(),
      dl.delete_attribute_if(fn(key, _) {
        writerly.is_commented_attribute_key(key)
      }),
      dl.unwrap_if_first_child("WriterlyBlankLine"),
      dl.append(#("Proof", "QED", infra.Continue)),
      dl.replace_with_arbitrary(#("QED", qed)),
      dl.prepend_attribute_as_wrapped_text(#("Definition", "label", label_span)),
      dl.prepend_attribute_as_wrapped_text(#("Example", "label", label_span)),
      dl.prepend_attribute_as_wrapped_text(#("Theorem", "label", label_span)),
      dl.prepend_attribute_as_wrapped_text(#("Lemma", "label", label_span)),
      dl.prepend_attribute_as_wrapped_text(#("Corollary", "label", label_span)),
      dl.rename_with_attributes__batch([
        #("Definition", "Statement", [
          #("title", "*Definition*"),
          #("class", "statement definition"),
        ]),
        #("Example", "Statement", [
          #("title", "*Example*"),
          #("class", "statement example"),
        ]),
        #("Exercise", "Statement", [
          #("title", "*Exercise*"),
          #("class", "statement exercise"),
        ]),
        #("Lemma", "Statement", [
          #("title", "*Lemma*"),
          #("class", "statement lemma"),
        ]),
        #("Theorem", "Statement", [
          #("title", "*Theorem*"),
          #("class", "statement theorem"),
        ]),
        #("Corollary", "Statement", [
          #("title", "*Corollary*"),
          #("class", "statement corollary"),
        ]),
      ]),
      dl.append_attribute__batch([
        #("Document", "counter", "ChapterCounter"),
        #("Chapter", "counter", "SectionCounter"),
        #("Chapter", "counter", "StatementCounter"),
        #("Chapter", "counter", "FootnoteCounter"),
        #("Section", "counter", "SubSectionCounter"),
        #("Section", "counter", "FootnoteCounter"),
        #("SubSection", "counter", "FootnoteCounter"),
        #("Exercises", "counter", "FootnoteCounter"),
        #("Bibliography", "counter", "FootnoteCounter"),
      ]),
      dl.prepend_attribute__batch([
        #("Chapter", "path", "./::øøChapterCounter-0.html"),
        #("Section", "path", "./::øøChapterCounter-::øøSectionCounter.html"),
        #(
          "SubSection",
          "path",
          "./::øøChapterCounter-::øøSectionCounter-::øøSubSectionCounter.html",
        ),
        #("Exercises", "path", "./exercises.html"),
        #("Bibliography", "path", "./bibliography.html"),
      ]),
      dl.sigil_counters_prepend_incrementing_attribute__batch([
        #("Chapter", "ChapterCounter"),
        #("Section", "SectionCounter"),
        #("SubSection", "SubSectionCounter"),
        #("Statement", "StatementCounter"),
        #("Footnote", "FootnoteCounter"),
      ]),
      dl.auto_generate_child_if_missing_from_attribute__batch([
        #("Chapter", "ChapterTitle", "title"),
        #("Section", "SectionTitle", "title"),
        #("SubSection", "SubSectionTitle", "title"),
        #("Exercises", "ExercisesTitle", "title"),
        #("Bibliography", "BibliographyTitle", "title"),
      ]),
      dl.writerly_handles_set_value__batch([
        #("Chapter", "::øøChapterCounter"),
        #("Section", "::øøChapterCounter.::øøSectionCounter"),
        #(
          "SubSection",
          "::øøChapterCounter.::øøSectionCounter.::øøSubSectionCounter",
        ),
        #("Statement", "::øøChapterCounter.::øøStatementCounter"),
        #("Footnote", "::øøFootnoteCounter"),
      ]),
      local_dl.dr_create_index(),
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
    ],
    syntax.create_mathblock_elements(
      list.flatten([
        [infra.DoubleDollar],
        formatter_pipeline.recognized_display_delimiters(),
      ]),
      infra.DoubleDollar,
      ["WriterlyBlankLine", "Indent"],
    ),
    [
      local_dl.dr_footnote_marker_to_sup_handle__outside("FootnoteCounter", [
        "MathBlock",
        "Math",
      ]),
    ],
    syntax.markdown_link_pipeline(["WriterlyBlankLine", "Indent"], ["MathBlock"]),
    [
      dl.writerly_handles_materialize_mathjax_tags(#(
        "MathBlock",
        "::++EquationCounter",
      )),
      dl.sigil_counters_substitute__outside(["pre"]),
      dl.writerly_handles_generate_v_definitions_from_t_definitions(),
      local_dl.dr_create_menu(),
      dl.writerly_handles_add_ids(),
      dl.writerly_handles_grand_wrapper_generate_dictionary("path"),
      dl.writerly_handles_grand_wrapper_substitute(
        #("path", "a", "a", [], [], ["a"], ["Math", "MathBlock"]),
      ),
      dl.writerly_handles_grand_wrapper_warn_unused(["MathBlock"]),
      dl.writerly_handles_grand_wrapper_unwrap(),
    ],
    syntax.create_math_elements(
      [infra.BackslashParenthesis, infra.SingleDollar],
      infra.SingleDollar,
      infra.BackslashParenthesis,
      ["WriterlyBlankLine", "Indent"],
    ),
    [
      dl.tokenize_href_surroundings(),
      dl.rearrange_links_4_pre_tokenized_src__batch([
        #("Lemma <a href=1>_1_</a>", "<a href=1>Lemma _1_</a>"),
        #("Section <a href=1>_1_</a>", "<a href=1>Section _1_</a>"),
        #("Subsection <a href=1>_1_</a>", "<a href=1>Subsection _1_</a>"),
        #("Theorem <a href=1>_1_</a>", "<a href=1>Theorem _1_</a>"),
      ]),
      dl.detokenize_href_surroundings(),
      dl.rearrange_links__batch([
        #("(<a href=0>_0_</a>)", "<a href=0>(_0_)</a>"),
        #("(<a href=0>_0_</a>).", "<a href=0>(_0_)</a>."),
        #("(<a href=0>_0_</a>),", "<a href=0>(_0_)</a>,"),
        #("(<a href=0>_0_</a>))", "<a href=0>(_0_)</a>)"),
        #("(<a href=0>_0_</a>)).", "<a href=0>(_0_)</a>)."),
      ]),
    ],
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
      dl.unescape_delimiters__outside(["_", "*"], ["Math", "MathBlock"]),
    ],
    case author_mode {
      False -> []
      True -> [
        dl.source_provenance_wrap_lines__outside(
          #(parameters.input_dir, [#("class", "t-3003-c")], [
            #("class", "t-3003"),
          ]),
          ["Math", "MathBlock", "Navigation", "Index"],
        ),
        dl.source_provenance_append_img_spans(
          #(
            parameters.output_dir,
            "original",
            ["img", "figure", "Carousel"],
            [#("class", "t-3003 t-3003-i")],
            [#("class", "t-3003-i-url")],
          ),
        ),
        dl.source_provenance_append_span(
          #(parameters.input_dir, [#("class", "t-3003")], ["MathBlock"]),
        ),
        dl.source_provenance_wrap(
          #(
            parameters.input_dir,
            "span",
            [#("class", "t-3003-c")],
            [#("class", "t-3003")],
            ["Math"],
          ),
        ),
      ]
    },
    [
      dl.fold_contents_into_text("Math"),
      dl.find_replace_if_has_ancestor_else(#(
        ["Math", "MathBlock"],
        #("``", "“"),
        #("``", "\""),
      )),
      dl.find_replace_if_has_ancestor_else(#(
        ["Math", "MathBlock"],
        #("''", "”"),
        #("''", "\""),
      )),
      dl.group_consecutive_children__outside(
        #("p", p_cannot_contain),
        p_cannot_be_contained_in,
      ),
      dl.unwrap("WriterlyBlankLine"),
      dl.trim("p"),
      dl.delete_if_empty("p"),
      dl.add_class_to_next_sibling(#("Indent", "indent")),
      dl.append_class__batch([
        #("MathBlock", "math-block"),
      ]),
      dl.append_class__batch([
        #("Index", "index"),
        #("Chapter", "chapter"),
        #("Section", "section"),
        #("SubSection", "subsection"),
        #("Footnote", "footnote"),
        #("Exercises", "exercises"),
        #("Bibliography", "bibliography"),
      ]),
      local_dl.dr_generate_js_course(course),
      dl.rename__batch([
        #("Chapter", "div"),
        #("ChapterTitle", "h1"),
        #("Index", "div"),
        #("Labeled", "div"),
        #("MathBlock", "div"),
        #("Navigation", "div"),
        #("Proof", "div"),
        #("Section", "div"),
        #("SectionTitle", "h1"),
        #("Statement", "div"),
        #("SubSection", "div"),
        #("SubSectionTitle", "h1"),
        #("Footnote", "div"),
        #("Exercises", "div"),
        #("ExercisesTitle", "h1"),
        #("Bibliography", "div"),
        #("BibliographyTitle", "h1"),
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
