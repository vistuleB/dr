import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugaringError, type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import on
import vxml.{type VXML, Attr, V}

pub const name = "dr_create_menu"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends previous, index, and next navigation links to
/// each generated course page.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

// ---- Page address types ----

type PageAddr {
  ChapterAddr(ch_no: Int)
  SectionAddr(ch_no: Int, sec_no: Int)
  SubSectionAddr(ch_no: Int, sec_no: Int, sub_no: Int)
  ExercisesAddr
  BibliographyAddr
}

fn page_href(addr: PageAddr) -> String {
  case addr {
    ChapterAddr(ch) -> "./" <> int.to_string(ch) <> "-0.html"
    SectionAddr(ch, sec) ->
      "./" <> int.to_string(ch) <> "-" <> int.to_string(sec) <> ".html"
    SubSectionAddr(ch, sec, sub) ->
      "./"
      <> int.to_string(ch)
      <> "-"
      <> int.to_string(sec)
      <> "-"
      <> int.to_string(sub)
      <> ".html"
    ExercisesAddr -> "./exercises.html"
    BibliographyAddr -> "./bibliography.html"
  }
}

// A Chapter has content when there are nodes between its optional ChapterTitle
// and its first Section child.
fn chapter_has_content(vxml: VXML) -> Bool {
  let assert V(_, "Chapter", _, children) = vxml
  case children {
    [] -> False
    [V(_, "ChapterTitle", _, _)] -> False
    [V(_, "Section", _, _), ..] -> False
    [V(_, "ChapterTitle", _, _), V(_, "Section", _, _), ..] -> False
    _ -> True
  }
}

// ---- Pass 1: Gather pages in order ----

type GatherState {
  GatherState(pages: List(PageAddr), ch_no: Int, sec_no: Int, sub_no: Int)
}

fn gather_nodemap(
  vxml: VXML,
  state: GatherState,
) -> Result(#(GatherState, TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) -> Ok(#(state, Continue))
    V(_, "Chapter", _, _) -> {
      let new_ch = state.ch_no + 1
      let base = GatherState(..state, ch_no: new_ch, sec_no: 0, sub_no: 0)
      let new_state = case chapter_has_content(vxml) {
        False -> base
        True -> GatherState(..base, pages: [ChapterAddr(new_ch), ..base.pages])
      }
      Ok(#(new_state, Continue))
    }
    V(_, "Section", _, _) -> {
      let new_sec = state.sec_no + 1
      let addr = SectionAddr(state.ch_no, new_sec)
      Ok(#(
        GatherState(..state, sec_no: new_sec, sub_no: 0, pages: [
          addr,
          ..state.pages
        ]),
        Continue,
      ))
    }
    V(_, "SubSection", _, _) -> {
      let new_sub = state.sub_no + 1
      let addr = SubSectionAddr(state.ch_no, state.sec_no, new_sub)
      Ok(#(
        GatherState(..state, sub_no: new_sub, pages: [addr, ..state.pages]),
        GoBack,
      ))
    }
    V(_, "Exercises", _, _) -> {
      Ok(#(GatherState(..state, pages: [ExercisesAddr, ..state.pages]), GoBack))
    }
    V(_, "Bibliography", _, _) -> {
      Ok(#(
        GatherState(..state, pages: [BibliographyAddr, ..state.pages]),
        GoBack,
      ))
    }
    _ -> Ok(#(state, GoBack))
  }
}

fn gather_pages(root: VXML) -> Result(List(PageAddr), DesugaringError) {
  use final_state <- on.ok(n2t.early_return_stateful_visit(
    root,
    GatherState(pages: [], ch_no: 0, sec_no: 0, sub_no: 0),
    gather_nodemap,
  ))
  Ok(list.reverse(final_state.pages))
}

// ---- Build nav dict ----

fn build_nav_entries(
  pages: List(PageAddr),
  hrefs: List(String),
  prev_href: Option(String),
) -> List(#(PageAddr, #(Option(String), Option(String)))) {
  case pages, hrefs {
    [], _ -> []
    [page, ..rest_pages], [href, ..rest_hrefs] -> {
      let next_href = case rest_hrefs {
        [] -> None
        [next, ..] -> Some(next)
      }
      [
        #(page, #(prev_href, next_href)),
        ..build_nav_entries(rest_pages, rest_hrefs, Some(href))
      ]
    }
    _, _ -> []
  }
}

fn build_nav_dict(
  pages: List(PageAddr),
) -> Dict(PageAddr, #(Option(String), Option(String))) {
  let hrefs = list.map(pages, page_href)
  build_nav_entries(pages, hrefs, Some("./index.html"))
  |> dict.from_list
}

// ---- Navigation node construction ----

fn anchor(id: String, href: String) -> VXML {
  let b = authoring.blame(name, 166)
  V(b, "a", [Attr(b, "id", id), Attr(b, "href", href)], [])
}

fn make_navigation(
  prev_href: Option(String),
  next_href: Option(String),
) -> VXML {
  let b = authoring.blame(name, 174)
  let links =
    [
      prev_href |> option.map(fn(h) { anchor("prev-page", h) }),
      // always present; the stylesheet decides where it is shown. On a
      // pointer device the `0` key already jumps to the index.
      Some(anchor("index-page", "./index.html")),
      next_href |> option.map(fn(h) { anchor("next-page", h) }),
    ]
    |> option.values
  V(b, "Navigation", [Attr(b, "class", "nav")], links)
}

// ---- Pass 2: Transform ----

// state = (ch_no, sec_no, sub_no) — all start at 0
type TransformState =
  #(Int, Int, Int)

fn v_before(
  nav_dict: Dict(PageAddr, #(Option(String), Option(String))),
  node: VXML,
  state: TransformState,
) -> #(VXML, TransformState) {
  let #(ch, sec, sub) = state
  case node {
    V(_, "Document", _, _) -> #(node, state)
    V(_, "Chapter", _, _) -> {
      let new_ch = ch + 1
      case chapter_has_content(node) {
        False -> #(node, #(new_ch, 0, 0))
        True -> {
          let addr = ChapterAddr(new_ch)
          let #(prev_href, next_href) =
            result.unwrap(dict.get(nav_dict, addr), #(None, None))
          let nav = make_navigation(prev_href, next_href)
          #(core.v_prepend_child(node, nav), #(new_ch, 0, 0))
        }
      }
    }
    V(_, "Section", _, _) -> {
      let new_sec = sec + 1
      let addr = SectionAddr(ch, new_sec)
      let #(prev_href, next_href) =
        result.unwrap(dict.get(nav_dict, addr), #(None, None))
      let nav = make_navigation(prev_href, next_href)
      #(core.v_prepend_child(node, nav), #(ch, new_sec, 0))
    }
    V(_, "SubSection", _, _) -> {
      let new_sub = sub + 1
      let addr = SubSectionAddr(ch, sec, new_sub)
      let #(prev_href, next_href) =
        result.unwrap(dict.get(nav_dict, addr), #(None, None))
      let nav = make_navigation(prev_href, next_href)
      #(core.v_prepend_child(node, nav), #(ch, sec, new_sub))
    }
    V(_, "Exercises", _, _) -> {
      let #(prev_href, next_href) =
        result.unwrap(dict.get(nav_dict, ExercisesAddr), #(None, None))
      let nav = make_navigation(prev_href, next_href)
      #(core.v_prepend_child(node, nav), state)
    }
    V(_, "Bibliography", _, _) -> {
      let #(prev_href, next_href) =
        result.unwrap(dict.get(nav_dict, BibliographyAddr), #(None, None))
      let nav = make_navigation(prev_href, next_href)
      #(core.v_prepend_child(node, nav), state)
    }
    _ -> #(node, state)
  }
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  use pages <- on.ok(gather_pages(root))
  let nav_dict = build_nav_dict(pages)
  let nm =
    n2t.OneToOneEnterExitStatefulNoErrorNodemap(
      on_enter: fn(v, s) { v_before(nav_dict, v, s) },
      on_exit: fn(v, _, latest) { #(v, latest) },
      on_text: fn(v, s) { #(v, s) },
    )
  let transform =
    n2t.one_to_one_enter_exit_stateful_no_error_nodemap_2_desugarer_transform(
      nm,
      #(0, 0, 0),
    )
  use #(vxml, _) <- on.ok(transform(root))
  Ok(vxml)
}

fn inner_param_to_transform() -> core.DesugarerTransform {
  at_root
  |> n2t.node_to_node_2_desugarer_transform_without_walking
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  [
    core.AssertiveTestDataNoParam(
      source: "
                <> Document
                  <> Chapter
                    <> Section
                    <> Section
                ",
      expected: "
                <> Document
                  <> Chapter
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./index.html
                        <> a
                          id=index-page
                          href=./index.html
                        <> a
                          id=next-page
                          href=./1-2.html
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./1-1.html
                        <> a
                          id=index-page
                          href=./index.html
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                <> Document
                  <> Chapter
                    <> Section
                    <> Section
                  <> Chapter
                    <> Section
                    <> Section
                      <> SubSection
                      <> SubSection
                      <> SubSection
                  <> Chapter
                    <> Section
                ",
      expected: "
                <> Document
                  <> Chapter
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./index.html
                        <> a
                          id=index-page
                          href=./index.html
                        <> a
                          id=next-page
                          href=./1-2.html
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./1-1.html
                        <> a
                          id=index-page
                          href=./index.html
                        <> a
                          id=next-page
                          href=./2-1.html
                  <> Chapter
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./1-2.html
                        <> a
                          id=index-page
                          href=./index.html
                        <> a
                          id=next-page
                          href=./2-2.html
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./2-1.html
                        <> a
                          id=index-page
                          href=./index.html
                        <> a
                          id=next-page
                          href=./2-2-1.html
                      <> SubSection
                        <> Navigation
                          class=nav
                          <> a
                            id=prev-page
                            href=./2-2.html
                          <> a
                            id=index-page
                            href=./index.html
                          <> a
                            id=next-page
                            href=./2-2-2.html
                      <> SubSection
                        <> Navigation
                          class=nav
                          <> a
                            id=prev-page
                            href=./2-2-1.html
                          <> a
                            id=index-page
                            href=./index.html
                          <> a
                            id=next-page
                            href=./2-2-3.html
                      <> SubSection
                        <> Navigation
                          class=nav
                          <> a
                            id=prev-page
                            href=./2-2-2.html
                          <> a
                            id=index-page
                            href=./index.html
                          <> a
                            id=next-page
                            href=./3-1.html
                  <> Chapter
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./2-2-3.html
                        <> a
                          id=index-page
                          href=./index.html
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                <> Document
                  <> Chapter
                    <> SomeContent
                    <> Section
                    <> Section
                  <> Chapter
                    <> Section
                ",
      expected: "
                <> Document
                  <> Chapter
                    <> Navigation
                      class=nav
                      <> a
                        id=prev-page
                        href=./index.html
                      <> a
                        id=index-page
                        href=./index.html
                      <> a
                        id=next-page
                        href=./1-1.html
                    <> SomeContent
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./1-0.html
                        <> a
                          id=index-page
                          href=./index.html
                        <> a
                          id=next-page
                          href=./1-2.html
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./1-1.html
                        <> a
                          id=index-page
                          href=./index.html
                        <> a
                          id=next-page
                          href=./2-1.html
                  <> Chapter
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./1-2.html
                        <> a
                          id=index-page
                          href=./index.html
                ",
    ),
    core.AssertiveTestDataNoParam(
      source: "
                <> Document
                  <> Chapter
                    <> ChapterTitle
                    <> Section
                  <> Chapter
                    <> ChapterTitle
                    <> SomeContent
                    <> Section
                ",
      expected: "
                <> Document
                  <> Chapter
                    <> ChapterTitle
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./index.html
                        <> a
                          id=index-page
                          href=./index.html
                        <> a
                          id=next-page
                          href=./2-0.html
                  <> Chapter
                    <> Navigation
                      class=nav
                      <> a
                        id=prev-page
                        href=./1-1.html
                      <> a
                        id=index-page
                        href=./index.html
                      <> a
                        id=next-page
                        href=./2-1.html
                    <> ChapterTitle
                    <> SomeContent
                    <> Section
                      <> Navigation
                        class=nav
                        <> a
                          id=prev-page
                          href=./2-0.html
                        <> a
                          id=index-page
                          href=./index.html
                ",
    ),
  ]
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
