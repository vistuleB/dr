import gleam/list
import gleam/option
import gleam/string
import vxml.{type VXML, Attr, V}
import vxml/blame.{type Blame}
import vxml_pipeline/authoring
import vxml_pipeline/core.{type Desugarer, type DesugaringError}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "dr_insert_cover_image"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Inserts the Document's `cover` image into the dr Index page (between the
/// header and the table of contents). No-op when the Document has no `cover`
/// attribute. A bare filename resolves against the `figures/` directory.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(name: name, transform: inner_param_to_transform())
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 header 🌸
// 🌸🌸🌸🌸🌸🌸🌸

// Resolve a `cover` attribute value into an `<img>` `src`. A bare filename
// defaults to the `figures/` directory (the dr figure convention, shared by
// every in-body `<img src=figures/...>`); a value that already carries an
// explicit path or URL (i.e. contains a `/`) is used verbatim.
fn resolve_src(cover: String) -> String {
  case string.contains(cover, "/") {
    True -> cover
    False -> "figures/" <> cover
  }
}

fn cover_img(b: Blame, cover: String) -> VXML {
  V(
    b,
    "img",
    [
      Attr(b, "class", "index__cover"),
      Attr(b, "src", resolve_src(cover)),
    ],
    [],
  )
}

// Place the cover image right after the Index's `header` child, so it sits
// between the title/author block and the table of contents (mirroring the
// original lecture-notes title page). If the Index has no `header` (should not
// happen in the dr layout), the cover is prepended as a safe fallback.
fn insert_after_header(index_children: List(VXML), img: VXML) -> List(VXML) {
  case
    list.split_while(index_children, fn(child) {
      case child {
        V(_, "header", _, _) -> False
        _ -> True
      }
    })
  {
    #(before, [header, ..after]) -> list.flatten([before, [header, img], after])
    #(_, []) -> [img, ..index_children]
  }
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, "Document", _, children) = root
  case core.v_first_attr_with_key(root, "cover") {
    // A Document without a `cover` attribute is left untouched (no image).
    option.None -> Ok(root)
    option.Some(cover) -> {
      let img = cover_img(cover.blame, cover.val)
      let children =
        list.map(children, fn(child) {
          case child {
            V(b, "Index", attrs, index_children) ->
              V(b, "Index", attrs, insert_after_header(index_children, img))
            _ -> child
          }
        })
      Ok(V(..root, children: children))
    }
  }
}

fn inner_param_to_transform() -> core.DesugarerTransform {
  at_root
  |> n2t.node_to_node_2_desugarer_transform_without_walking
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    // bare filename -> figures/ prefix, inserted after the header
    testing.data_no_param(
      source: "
        <> Document
          cover=optimalswitching.png
          <> Index
            <> Navigation
            <> header
            <> ol
      ",
      expected: "
        <> Document
          cover=optimalswitching.png
          <> Index
            <> Navigation
            <> header
            <> img
              class=index__cover
              src=figures/optimalswitching.png
            <> ol
      ",
    ),
    // no cover attribute -> document untouched
    testing.data_no_param(
      source: "
        <> Document
          <> Index
            <> header
            <> ol
      ",
      expected: "
        <> Document
          <> Index
            <> header
            <> ol
      ",
    ),
    // explicit path (contains a '/') -> used verbatim, no figures/ prefix
    testing.data_no_param(
      source: "
        <> Document
          cover=assets/front.svg
          <> Index
            <> header
            <> ol
      ",
      expected: "
        <> Document
          cover=assets/front.svg
          <> Index
            <> header
            <> img
              class=index__cover
              src=assets/front.svg
            <> ol
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
