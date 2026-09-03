import gleam/list
import gleam/option.{None, Some}
import gleam/regexp.{type Regexp}
import gleam/string
import vxml.{type Line, type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame} as bl
import vxml_pipeline/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

const originator_suffix = "-originator"

fn split_content(blame: Blame, content: String, re: Regexp) -> List(VXML) {
  case content {
    "" -> []
    _ -> split_nonempty_content(blame, content, re)
  }
}

import vxml_pipeline/authoring

fn split_nonempty_content(
  blame: Blame,
  content: String,
  re: Regexp,
) -> List(VXML) {
  case regexp.scan(re, content) {
    [] -> [T(blame, [Line(blame, content)])]
    [first_match, ..] ->
      case first_match.submatches {
        [Some(handle_name)] ->
          case string.split_once(content, first_match.content) {
            Error(_) -> [T(blame, [Line(blame, content)])]
            Ok(#(before, after)) -> {
              let before_len = string.length(before)
              let match_len = string.length(first_match.content)
              let sup_blame = bl.advance(blame, before_len)
              let after_blame = bl.advance(blame, before_len + match_len)
              let sup_node =
                V(
                  sup_blame,
                  "sup",
                  [Attr(sup_blame, "handle", handle_name <> originator_suffix)],
                  [T(sup_blame, [Line(sup_blame, "(>>" <> handle_name <> ")")])],
                )
              let before_nodes = case before {
                "" -> []
                _ -> [T(blame, [Line(blame, before)])]
              }
              list.flatten([
                before_nodes,
                [sup_node],
                split_content(after_blame, after, re),
              ])
            }
          }
        _ -> [T(blame, [Line(blame, content)])]
      }
  }
}

fn line_nodemap(line: Line, re: Regexp) -> List(VXML) {
  split_content(line.blame, line.content, re)
}

fn footnote_own_handle_name(vxml: VXML) -> option.Option(String) {
  case core.v_first_attr_with_key(vxml, "handle") {
    None -> None
    Some(handle_attr) ->
      case string.split_once(handle_attr.val, " ") {
        Ok(#(name, _)) -> Some(name)
        Error(_) -> Some(handle_attr.val)
      }
  }
}

fn prepend_backlink_to_footnote(vxml: VXML, counter_name: String) -> VXML {
  case footnote_own_handle_name(vxml) {
    None -> vxml
    Some(handle_name) -> {
      let assert V(blame, _, _, children) = vxml
      let backlink_text =
        "[(::øø"
        <> counter_name
        <> ")](>>"
        <> handle_name
        <> originator_suffix
        <> ") "
      let backlink_node = T(blame, [Line(blame, backlink_text)])
      V(..vxml, children: [backlink_node, ..children])
    }
  }
}

fn nodemap(vxml: VXML, inner: InnerParam) -> List(VXML) {
  let #(re, counter_name) = inner
  case vxml {
    V(_, "Footnote", _, _) -> [prepend_backlink_to_footnote(vxml, counter_name)]
    V(_, _, _, _) -> [vxml]
    T(_, lines) ->
      lines
      |> list.flat_map(line_nodemap(_, re))
      |> core.plain_concatenation_in_list
  }
}

fn inner_param_to_transform(
  inner: InnerParam,
  outside: List(String),
) -> DesugarerTransform {
  let nodemap: n2t.OneToManyNoErrorNodemap = nodemap(_, inner)
  nodemap
  |> n2t.one_to_many_no_error_nodemap_2_desugarer_transform_outside(outside)
}

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  let pattern = "\\(\\*>>([a-zA-Z0-9_.:^\\-']+(?:#[a-zA-Z0-9_:\\-]+)*)\\)"
  let assert Ok(re) =
    regexp.compile(
      pattern,
      regexp.Options(case_insensitive: False, multi_line: False),
    )
  Ok(#(re, param))
}

// Bare counter name, such as "FootnoteCounter". This is not an
// increment expression: this desugarer only reads the counter
// with `::øø`; `sigil_counters_prepend_incrementing_attribute`
// increments it at the `Footnote` node.
type Param =
  String

type InnerParam =
  #(Regexp, String)

pub const name = "dr_footnote_marker_to_sup_handle__outside"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Two independent, local rewrites in one pass:
///
/// 1. T-node text `(*>>handle_name)` becomes
///    ```
///    <> sup
///        handle=handle_name-originator
///        <>
///            '(>>handle_name)'
///    ```
///    `handle_name` is expected to be independently
///    defined elsewhere (on a `Footnote` node, via a
///    bare `handle=handle_name` attribute whose value
///    gets filled in by `writerly_handles_set_value` reading a
///    counter incremented at that same `Footnote`
///    node) — so `(>>handle_name)` resolves to
///    `(<a href=...>N</a>)` via the ordinary
///    `writerly_handles_grand_wrapper_substitute` text-reference
///    mechanism.
///    The `handle=handle_name-originator` attribute
///    makes the sup itself independently addressable,
///    for the reverse link (see below).
///
/// 2. Every `Footnote` V-node gets a new first T-node
///    child prepended:
///    ```
///    [(::øøcounter_name)](>>handle_name-originator)
///    ```
///    where `handle_name` is read off that SAME
///    `Footnote` node's own `handle` attribute. This is
///    markdown-link syntax whose URL is a handle
///    reference — once `markdown_link_pipeline` (which
///    must run AFTER this desugarer) turns it into a
///    real `<a>`, `writerly_handles_grand_wrapper_substitute`'s
///    href-rewriting
///    (the same mechanism that resolves
///    `href=>>handle_name` on any `<a>` tag) resolves it
///    to the sup's own id, giving a working backlink.
///
/// Callers still need, elsewhere in the pipeline:
///   - `sigil_counters_prepend_incrementing_attribute` on
///     `Footnote` (increments `counter_name` at each
///     `Footnote` node, in document order)
///   - `writerly_handles_set_value` on `Footnote` reading
///     `::øøcounter_name` (assigns that just-incremented
///     value to the node's own bare `handle=` attribute)
///   - `rearrange_links__batch` with
///     `#("(<a href=0>_0_</a>)", "<a href=0>(_0_)</a>")`
///     (run after `writerly_handles_grand_wrapper_substitute`) to make the
///     parens around the sup's own `(N)` part of the
///     link, not just the bare number
///
/// keeps the T-node rewrite (1) out of subtrees rooted
/// at tags given by its second argument
pub fn constructor(param: Param, outside: List(String)) -> Desugarer {
  authoring.desugarer_with_outside(
    name: name,
    param: param,
    outside: outside,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataWithOutside(Param)) {
  [
    // Test 1: basic match, mid-sentence
    testing.data_with_outside(
      param: "FootnoteCounter",
      outside: [],
      source: "
        <> root
          <>
            'Fourier transform(*>>fn-fourier-transform) of f'
        ",
      expected: "
        <> root
          <>
            'Fourier transform'
          <> sup
            handle=fn-fourier-transform-originator
            <>
              '(>>fn-fourier-transform)'
          <>
            ' of f'
        ",
    ),

    // Test 2: no match -> unchanged
    testing.data_with_outside(
      param: "FootnoteCounter",
      outside: [],
      source: "
        <> root
          <>
            'nothing to see here'
        ",
      expected: "
        <> root
          <>
            'nothing to see here'
        ",
    ),

    // Test 3: two matches on the same line
    testing.data_with_outside(
      param: "FootnoteCounter",
      outside: [],
      source: "
        <> root
          <>
            'a(*>>fn-one) and b(*>>fn-two)'
        ",
      expected: "
        <> root
          <>
            'a'
          <> sup
            handle=fn-one-originator
            <>
              '(>>fn-one)'
          <>
            ' and b'
          <> sup
            handle=fn-two-originator
            <>
              '(>>fn-two)'
        ",
    ),

    // Test 4: match inside a forbidden ancestor -> unchanged
    testing.data_with_outside(
      param: "FootnoteCounter",
      outside: ["MathBlock"],
      source: "
        <> root
          <> MathBlock
            <>
              'a(*>>fn-one) b'
        ",
      expected: "
        <> root
          <> MathBlock
            <>
              'a(*>>fn-one) b'
        ",
    ),

    // Test 5: Footnote node gets a prepended backlink
    testing.data_with_outside(
      param: "FootnoteCounter",
      outside: [],
      source: "
        <> root
          <> Footnote
            handle=bob
            <>
              'Some footnote text.'
        ",
      expected: "
        <> root
          <> Footnote
            handle=bob
            <>
              '[(::øøFootnoteCounter)](>>bob-originator) '
            <>
              'Some footnote text.'
        ",
    ),

    // Test 6: Footnote node with no handle attr -> unchanged
    testing.data_with_outside(
      param: "FootnoteCounter",
      outside: [],
      source: "
        <> root
          <> Footnote
            <>
              'Some footnote text.'
        ",
      expected: "
        <> root
          <> Footnote
            <>
              'Some footnote text.'
        ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_with_outside(name, assertive_tests_data(), constructor)
}
