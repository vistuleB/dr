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

pub fn pipeline(course: String) -> List(infra.Desugarer) {
  let pre_transformation_document_tags = [
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
      vxml.T(our_blame, [vxml.Line(our_blame, "\\(\\square\\)")]),
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
      dl.delete_attribute_if(fn(key, _) { string.starts_with(key, "!!") }),
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
      ]),
      dl.prepend_attribute(#(
        "Chapter",
        "path",
        "./::øøChapterCounter-0.html",
        infra.GoBack,
      )),
      dl.prepend_attribute(#(
        "Section",
        "path",
        "./::øøChapterCounter-::øøSectionCounter.html",
        infra.GoBack,
      )),
      dl.prepend_attribute(#(
        "SubSection",
        "path",
        "./::øøChapterCounter-::øøSectionCounter-::øøSubSectionCounter.html",
        infra.GoBack,
      )),
      dl.prepend_attribute(#(
        "Exercises",
        "path",
        "./exercises.html",
        infra.GoBack,
      )),
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
      dl.prepend_counter_incrementing_attribute(#(
        "Footnote",
        "FootnoteCounter",
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
      dl.auto_generate_child_if_missing_from_attribute(#(
        "Exercises",
        "ExercisesTitle",
        "title",
      )),
      dl.set_handle_value(#("Chapter", "::øøChapterCounter", infra.GoBack)),
      dl.set_handle_value(#(
        "Section",
        "::øøChapterCounter.::øøSectionCounter",
        infra.GoBack,
      )),
      dl.set_handle_value(#(
        "SubSection",
        "::øøChapterCounter.::øøSectionCounter.::øøSubSectionCounter",
        infra.GoBack,
      )),
      dl.set_handle_value(#(
        "Statement",
        "::øøChapterCounter.::øøStatementCounter",
        infra.Continue,
      )),
      dl.set_handle_value(#("Footnote", "::øøFootnoteCounter", infra.GoBack)),
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
    ],
    pp.create_mathblock_elements(
      [infra.DoubleDollar, infra.BeginEndAlign, infra.BeginEndAlignStar],
      infra.DoubleDollar,
    ),
    [
      // must run before markdown_link_splitting: it prepends
      // `[(::øøFootnoteCounter)](>>handle-originator) ` markdown-link
      // text to each `Footnote` node's content (linking back to the
      // sup via that sup's own handle=handle-originator attribute),
      // and wraps `(*>>handle)` call sites in `<sup handle=handle-
      // originator><>'(>>handle)'</></sup>`. FootnoteCounter itself is
      // incremented at the `Footnote` node above (prepend_counter_
      // incrementing_attribute), not here.
      dl.footnote_marker_to_sup_handle("FootnoteCounter", [
        "MathBlock",
        "Math",
      ]),
    ],
    pp.markdown_link_splitting(["MathBlock"]),
    [
      dl.math_label_to_tag_handle(#("MathBlock", "::++EquationCounter")),
      dl.substitute_counters(),
      dl.handles_generate_v_definitions_from_t_definitions(),
      dl.dr_create_menu(),
      dl.handles_add_ids(),
      dl.handles_generate_dictionary("path"),
      dl.handles_substitute(#("path", "a", "a", [], [], ["a"])),
      dl.unwrap("GrandWrapper"),
    ],
    // Parse inline math into Math nodes BEFORE href tokenization: pre-transformationtokenize_href_surroundings
    // only recurses into T-nodes and href-bearing V-nodes, so Math nodes are opaque to it.
    // This protects inline math like `$\max(X,0)$` from the paren tokenize/detokenize round-trip
    // (which otherwise corrupts a `\command(...)` group that is a sibling of a link node).
    pp.create_math_elements(
      [infra.BackslashParenthesis, infra.SingleDollar],
      infra.SingleDollar,
      infra.BackslashParenthesis,
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
      // pulls the literal parens the footnote_marker_to_sup_handle-
      // produced `(>>handle)` text leaves outside the <a> (once
      // handles_substitute turns it into `(<a href=...>N</a>)`) inside
      // the link, so the whole "(N)" is clickable, not just "N". Must
      // run after pp.create_math_elements above: rearrange_links does
      // its own internal tokenize/detokenize round-trip that treats
      // any non-href V-node as opaque, but raw un-parsed `$...$` text
      // is not yet opaque before create_math_elements runs, and gets
      // corrupted by the same class of bug fixed by moving
      // create_math_elements before tokenize_href_surroundings above.
      dl.rearrange_links__batch([
        #("(<a href=0>_0_</a>)", "<a href=0>(_0_)</a>"),
      ]),
    ],
    pp.barbaric_symmetric_delim_splitting("_", "_", "i", [
      "MathBlock",
      "Math",
    ]),
    pp.barbaric_symmetric_delim_splitting("\\*", "*", "b", [
      "MathBlock",
      "Math",
    ]),
    [
      // must come AFTER every splitting step above, or it would re-arm
      // delimiters that splitting just neutralized. "$" is deliberately
      // NOT escapable: browser-side MathJax re-scans the page, so a bare
      // "$" in prose would open math -- "\$" has to survive to the output.
      dl.unescape_delimiters__outside(["_", "*"], ["Math", "MathBlock"]),
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
        #("Footnote", "footnote"),
        #("Exercises", "exercises"),
      ]),
      dl.dr_generate_js_course(course),
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
