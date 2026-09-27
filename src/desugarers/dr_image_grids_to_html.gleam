import gleam/list
import gleam/option.{None, Some}
import vxml.{type VXML, Attr, V}
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
///   <figure class="image-grid" style="--columns: N">
///     <figure class="grid-image">
///       <img src="…" [style="max-width: P%"] [original="…"]>
///       <figcaption>(a)</figcaption>            (only if labelled)
///     </figure>
///     …
///     <figcaption>Figure 9: …</figcaption>      (the GridCaption)
///   </figure>
///
/// The layout itself lives in `shared/app.css` (`figure.image-grid`), which
/// sizes the cells from `--columns` with the same geometry as the LaTeX
/// renderer (`latex_renderer.image_grid_to_latex`).
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(name: name, transform: inner_param_to_transform())
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 header 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn grid_child_to_html(child: VXML) -> VXML {
  case child {
    V(b, "GridImage", attrs, label) -> {
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
    V(b, "GridCaption", _, children) -> V(b, "figcaption", [], children)
    _ -> child
  }
}

fn nodemap(node: VXML) -> VXML {
  case node {
    V(b, "ImageGrid", attrs, children) -> {
      let columns = case core.attrs_first_with_key(attrs, "columns") {
        Some(a) -> a.val
        None -> "2"
      }
      V(
        b,
        "figure",
        [Attr(b, "class", "image-grid"), Attr(b, "style", "--columns: " <> columns)],
        list.map(children, grid_child_to_html),
      )
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
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
