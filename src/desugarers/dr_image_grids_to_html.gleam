import gleam/list
import gleam/option.{None, Some}
import gleam/string
import vxml.{type Attr, type VXML, Attr, V}
import vxml/blame.{type Blame}
import vxml_pipeline/authoring
import vxml_pipeline/core.{type Desugarer}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "dr_image_grids_to_html"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Expands each `ImageGrid` into nested HTML figures. Expects the canonical
/// shape produced by `dr_normalize_image_grids`, which must run first:
///
///   <figure class="image-grid"
///           style="--columns: N[; --column-gap: G%][; --row-gap: L]">
///     <div class="grid-images">
///       <figure class="grid-image">
///         <img src="…" [style="max-width: P%"] [original="…"]>
///         <figcaption>(a)</figcaption>          (only if labelled)
///       </figure>
///       …
///     </div>
///     <figcaption>Figure 9: …</figcaption>      (the GridCaption)
///   </figure>
///
/// The images get their own row container so that `row-gap` separates only
/// the rows of images, not the last row from the caption (as in LaTeX). The
/// layout itself lives in `shared/app.css` (`figure.image-grid`), which sizes
/// the cells from the custom properties with the same geometry as the LaTeX
/// renderer (`latex_renderer.image_grid_to_latex`).
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(name: name, transform: inner_param_to_transform())
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 header 🌸
// 🌸🌸🌸🌸🌸🌸🌸

// the ImageGrid attributes that become CSS custom properties, in order
const layout_keys = ["columns", "column-gap", "row-gap"]

fn grid_image_to_html(b: Blame, attrs: List(Attr), label: List(VXML)) -> VXML {
  let img_attrs =
    attrs
    |> list.map(fn(a) {
      case a.key {
        "width" -> Attr(a.blame, "style", "max-width: " <> a.val)
        _ -> a
      }
    })
  let caption = case label {
    [] -> []
    _ -> [V(b, "figcaption", [], label)]
  }
  V(b, "figure", [Attr(b, "class", "grid-image")], [
    V(b, "img", img_attrs, []),
    ..caption
  ])
}

fn nodemap(node: VXML) -> VXML {
  case node {
    V(b, "ImageGrid", attrs, children) -> {
      let style =
        layout_keys
        |> list.filter_map(fn(key) {
          case core.attrs_first_with_key(attrs, key) {
            Some(a) -> Ok("--" <> key <> ": " <> a.val)
            None -> Error(Nil)
          }
        })
        |> string.join("; ")
      let images =
        list.filter_map(children, fn(c) {
          case c {
            V(cb, "GridImage", ca, label) -> Ok(grid_image_to_html(cb, ca, label))
            _ -> Error(Nil)
          }
        })
      let caption =
        list.filter_map(children, fn(c) {
          case c {
            V(cb, "GridCaption", _, cc) -> Ok(V(cb, "figcaption", [], cc))
            _ -> Error(Nil)
          }
        })
      V(b, "figure", [Attr(b, "class", "image-grid"), Attr(b, "style", style)], [
        V(b, "div", [Attr(b, "class", "grid-images")], images),
        ..caption
      ])
    }
    _ -> node
  }
}

fn inner_param_to_transform() -> core.DesugarerTransform {
  n2t.one_to_one_no_error_nodemap_2_desugarer_transform(nodemap)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    testing.data_no_param(
      source: "
        <> root
          <> ImageGrid
            columns=2
            <> GridImage
              src=figures/a.png
              <>
                '(a)'
            <> GridImage
              src=figures/b.png
              width=78%
            <> GridCaption
              <>
                'Figure 1: two maps.'
      ",
      expected: "
        <> root
          <> figure
            class=image-grid
            style=--columns: 2
            <> div
              class=grid-images
              <> figure
                class=grid-image
                <> img
                  src=figures/a.png
                <> figcaption
                  <>
                    '(a)'
              <> figure
                class=grid-image
                <> img
                  src=figures/b.png
                  style=max-width: 78%
            <> figcaption
              <>
                'Figure 1: two maps.'
      ",
    ),
    // the gaps become custom properties; no caption -> none emitted
    testing.data_no_param(
      source: "
        <> root
          <> ImageGrid
            columns=2
            column-gap=8%
            row-gap=1.5em
            <> GridImage
              src=figures/a.png
      ",
      expected: "
        <> root
          <> figure
            class=image-grid
            style=--columns: 2; --column-gap: 8%; --row-gap: 1.5em
            <> div
              class=grid-images
              <> figure
                class=grid-image
                <> img
                  src=figures/a.png
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
