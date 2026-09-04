import gleam/list
import gleam/regexp
import gleam/string
import vxml.{type VXML, Attr, V}
import vxml/blame.{Ext}
import vxml_pipeline/authoring
import vxml_pipeline/core.{type Desugarer}
import vxml_pipeline/testing

pub const name = "dr_latex_collect_document_context"

const equation_definition_pattern = "[A-Za-z][A-Za-z0-9_:-]*##<<"

fn equation_names(vxml: VXML) -> List(String) {
  case vxml {
    vxml.T(_, lines) -> {
      let text =
        lines |> list.map(fn(line) { line.content }) |> string.join("\n")
      let assert Ok(pattern) = regexp.from_string(equation_definition_pattern)
      regexp.scan(pattern, text)
      |> list.map(fn(found) { string.drop_end(found.content, 4) })
    }
    V(_, _, _, children) -> list.flat_map(children, equation_names)
  }
}

fn footnotes(vxml: VXML) -> List(VXML) {
  case vxml {
    vxml.T(_, _) -> []
    V(_, "Footnote", _, _) -> [vxml]
    V(_, _, _, children) -> list.flat_map(children, footnotes)
  }
}

fn transform(root: VXML) {
  let blame = Ext([], name)
  let equations =
    equation_names(root)
    |> list.map(fn(equation_name) {
      V(
        blame,
        "LatexEquationDefinition",
        [
          Attr(blame, "name", equation_name),
        ],
        [],
      )
    })
  let context =
    V(blame, "LatexContext", [], [
      V(blame, "LatexEquationDefinitions", [], equations),
      V(blame, "LatexFootnoteDefinitions", [], footnotes(root)),
    ])
  Ok(#(V(blame, "LatexPreparedDocument", [], [context, root]), []))
}

pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(name: name, transform: transform)
}

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    testing.data_no_param(
      source: "
        <> Document
          <> MathBlock
            <>
              'x=y eq:identity##<<'
          <> Footnote
            handle=note
            <>
              'Footnote body.'
      ",
      expected: "
        <> LatexPreparedDocument
          <> LatexContext
            <> LatexEquationDefinitions
              <> LatexEquationDefinition
                name=eq:identity
            <> LatexFootnoteDefinitions
              <> Footnote
                handle=note
                <>
                  'Footnote body.'
          <> Document
            <> MathBlock
              <>
                'x=y eq:identity##<<'
            <> Footnote
              handle=note
              <>
                'Footnote body.'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
