import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/regexp
import gleam/result
import gleam/string
import vxml.{type Attr, type VXML, Attr, T, V}
import vxml/blame.{type Blame}
import vxml_pipeline/authoring
import vxml_pipeline/core.{
  type Desugarer, type DesugaringError, DesugaringError,
}
import vxml_pipeline/nodemaps_2_transform as n2t
import vxml_pipeline/testing

pub const name = "dr_normalize_image_grids"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️

/// Validates the multi-image figure tags and puts them in one canonical shape,
/// which both renderers rely on (HTML: `dr_image_grids_to_html`; LaTeX:
/// `latex_renderer.image_grid_to_latex`):
///
///   ImageGrid  columns=N                       N >= 1, default 2
///              [column-gap=G%]                 % of the line, default 2%
///              [row-gap=<length>]              em/ex/pt/mm/cm/in
///     GridImage  src=… [width=P%] [original=…]  1 <= P <= 100
///       <label, e.g. "(a)">                    optional
///     …
///     GridCaption                              optional, last
///       <caption for the whole set>
///
/// Blank lines between and around the children are dropped. Anything else —
/// an unknown attribute (e.g. a leftover `style=`), an `img` inside a
/// `GridImage`, a `GridImage`/`GridCaption` outside an `ImageGrid`, a caption
/// that is not last — is an error pointing at the offending source line, so
/// the layout can never silently break in either renderer.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(name: name, transform: inner_param_to_transform())
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 header 🌸
// 🌸🌸🌸🌸🌸🌸🌸

const default_columns = "2"

// tags that make no sense inside an image's label or the set's caption
const structural_tags = [
  "img", "figure", "figcaption", "ImageGrid", "GridImage", "GridCaption",
]

fn fail(blame: Blame, message: String) -> Result(a, DesugaringError) {
  Error(DesugaringError(blame, message))
}

fn is_blank(node: VXML) -> Bool {
  case node {
    V(_, "WriterlyBlankLine", _, _) -> True
    T(_, lines) -> list.all(lines, fn(l) { string.trim(l.content) == "" })
    V(_, _, _, _) -> False
  }
}

fn is_grid_child(node: VXML) -> Bool {
  case node {
    V(_, "GridImage", _, _) | V(_, "GridCaption", _, _) -> True
    _ -> False
  }
}

fn trim_blanks(nodes: List(VXML)) -> List(VXML) {
  nodes
  |> list.drop_while(is_blank)
  |> list.reverse
  |> list.drop_while(is_blank)
  |> list.reverse
}

fn check_attrs(
  tag: String,
  attrs: List(Attr),
  allowed: List(String),
) -> Result(Nil, DesugaringError) {
  case list.find(attrs, fn(a) { !list.contains(allowed, a.key) }) {
    Error(Nil) -> Ok(Nil)
    Ok(a) ->
      fail(a.blame, case allowed {
        [] -> tag <> " takes no attributes, found '" <> a.key <> "'"
        _ ->
          tag
          <> " does not accept attribute '"
          <> a.key
          <> "' (allowed: "
          <> string.join(allowed, ", ")
          <> ")"
      })
  }
}

// the body of a GridImage (its label) or of a GridCaption: blank edges
// trimmed, and no nested images/figures/grid tags
fn check_body(
  tag: String,
  children: List(VXML),
  hint: String,
) -> Result(List(VXML), DesugaringError) {
  let children = trim_blanks(children)
  case
    list.find(children, fn(c) {
      case c {
        V(_, t, _, _) -> list.contains(structural_tags, t)
        T(_, _) -> False
      }
    })
  {
    Ok(V(b, t, _, _)) -> fail(b, "'" <> t <> "' cannot appear inside " <> tag <> hint)
    _ -> Ok(children)
  }
}

fn parse_positive_int(s: String) -> Result(Int, Nil) {
  case int.parse(string.trim(s)) {
    Ok(n) if n >= 1 -> Ok(n)
    _ -> Error(Nil)
  }
}

// "8%" -> 8 (a whole, non-negative percentage)
fn parse_percent(s: String) -> Result(Int, Nil) {
  case string.ends_with(s, "%"), int.parse(string.drop_end(s, 1)) {
    True, Ok(n) if n >= 0 -> Ok(n)
    _, _ -> Error(Nil)
  }
}

// a length both CSS and LaTeX read the same way, e.g. "1.5em"
fn is_length(s: String) -> Bool {
  let assert Ok(re) =
    regexp.from_string("^[0-9]+(\\.[0-9]+)?(em|ex|pt|mm|cm|in)$")
  regexp.check(re, s)
}

// Maps the (trimmed) value of each `key` attribute through `normalize`, which
// returns the canonical value, or a message reported at the attribute's blame.
fn normalize_attr(
  attrs: List(Attr),
  key: String,
  normalize: fn(String) -> Result(String, String),
) -> Result(List(Attr), DesugaringError) {
  list.try_map(attrs, fn(a) {
    case a.key == key {
      False -> Ok(a)
      True ->
        case normalize(string.trim(a.val)) {
          Ok(val) -> Ok(Attr(..a, val: val))
          Error(message) -> fail(a.blame, message <> ", got '" <> a.val <> "'")
        }
    }
  })
}

fn normalize_grid_image(
  blame: Blame,
  attrs: List(Attr),
  children: List(VXML),
) -> Result(VXML, DesugaringError) {
  use _ <- result.try(check_attrs("GridImage", attrs, ["src", "width", "original"]))
  // body first: a nested `img` explains a missing `src` better than "missing src"
  use label <- result.try(check_body(
    "GridImage",
    children,
    " (a GridImage takes its image from its own 'src' attribute; its body is only the label, e.g. \"(a)\")",
  ))
  use _ <- result.try(case core.attrs_first_with_key(attrs, "src") {
    None -> fail(blame, "GridImage is missing its required 'src' attribute")
    Some(a) ->
      case string.trim(a.val) {
        "" -> fail(a.blame, "GridImage has an empty 'src' attribute")
        _ -> Ok(Nil)
      }
  })
  use attrs <- result.try(
    normalize_attr(attrs, "width", fn(w) {
      case parse_percent(w) {
        Ok(pct) if pct >= 1 && pct <= 100 -> Ok(int.to_string(pct) <> "%")
        _ ->
          Error(
            "GridImage 'width' must be a percentage of its grid cell between 1% and 100%",
          )
      }
    }),
  )
  Ok(V(blame, "GridImage", attrs, label))
}

fn normalize_grid_caption(
  blame: Blame,
  attrs: List(Attr),
  children: List(VXML),
) -> Result(VXML, DesugaringError) {
  use _ <- result.try(check_attrs("GridCaption", attrs, []))
  use children <- result.try(check_body("GridCaption", children, ""))
  Ok(V(blame, "GridCaption", attrs, children))
}

fn normalize_grid_child(child: VXML) -> Result(VXML, DesugaringError) {
  case child {
    V(b, "GridImage", attrs, children) ->
      normalize_grid_image(b, attrs, children)
    V(b, "GridCaption", attrs, children) ->
      normalize_grid_caption(b, attrs, children)
    V(b, tag, _, _) ->
      fail(
        b,
        "ImageGrid may only contain GridImage and GridCaption children, found '"
          <> tag
          <> "'",
      )
    T(b, _) ->
      fail(
        b,
        "stray text inside ImageGrid: put each image's label inside its GridImage, and the caption for the whole set inside a GridCaption",
      )
  }
}

fn normalize_image_grid(
  blame: Blame,
  attrs: List(Attr),
  children: List(VXML),
) -> Result(VXML, DesugaringError) {
  use _ <- result.try(
    check_attrs("ImageGrid", attrs, ["columns", "column-gap", "row-gap"]),
  )
  let attrs = case core.attrs_first_with_key(attrs, "columns") {
    None -> list.append(attrs, [Attr(blame, "columns", default_columns)])
    Some(_) -> attrs
  }
  use attrs <- result.try(
    normalize_attr(attrs, "columns", fn(c) {
      case parse_positive_int(c) {
        Ok(n) -> Ok(int.to_string(n))
        Error(Nil) -> Error("ImageGrid 'columns' must be a positive whole number")
      }
    }),
  )
  let assert Some(Attr(_, _, columns)) =
    core.attrs_first_with_key(attrs, "columns")
  let assert Ok(columns) = int.parse(columns)
  // the cells and their gaps span 90% of the line, so the gaps must leave room
  use attrs <- result.try(
    normalize_attr(attrs, "column-gap", fn(g) {
      case parse_percent(g) {
        Ok(pct) if pct * { columns - 1 } < 90 -> Ok(int.to_string(pct) <> "%")
        Ok(_) ->
          Error(
            "ImageGrid 'column-gap' is too wide: the gaps between its "
            <> int.to_string(columns)
            <> " columns must total less than the 90% of the line the grid spans",
          )
        Error(Nil) ->
          Error(
            "ImageGrid 'column-gap' must be a whole percentage of the line width, e.g. 4%",
          )
      }
    }),
  )
  use attrs <- result.try(
    normalize_attr(attrs, "row-gap", fn(g) {
      case is_length(g) {
        True -> Ok(g)
        False ->
          Error(
            "ImageGrid 'row-gap' must be a length in em, ex, pt, mm, cm or in, e.g. 1.5em",
          )
      }
    }),
  )
  use children <- result.try(
    children
    |> list.filter(fn(c) { !is_blank(c) })
    |> list.try_map(normalize_grid_child),
  )
  use _ <- result.try(case list.reverse(children) {
    [_last, ..others] ->
      case list.find(others, core.is_v_and_tag_equals(_, "GridCaption")) {
        Ok(caption) ->
          fail(
            caption.blame,
            "GridCaption must be the last child of its ImageGrid (and an ImageGrid has at most one)",
          )
        Error(Nil) -> Ok(Nil)
      }
    [] -> Ok(Nil)
  })
  case list.any(children, core.is_v_and_tag_equals(_, "GridImage")) {
    True -> Ok(V(blame, "ImageGrid", attrs, children))
    False -> fail(blame, "ImageGrid needs at least one GridImage")
  }
}

// Bottom-up: an `ImageGrid` validates and rewrites its own children; any other
// element fails if it directly holds a `GridImage`/`GridCaption`, which are
// only meaningful as children of an `ImageGrid`.
fn nodemap(node: VXML) -> Result(VXML, DesugaringError) {
  case node {
    T(_, _) -> Ok(node)
    V(blame, "ImageGrid", attrs, children) ->
      normalize_image_grid(blame, attrs, children)
    V(_, tag, _, children) ->
      case list.find(children, is_grid_child) {
        Ok(V(b, t, _, _)) ->
          fail(
            b,
            t
              <> " must be a direct child of an ImageGrid (found inside '"
              <> tag
              <> "')",
          )
        _ -> Ok(node)
      }
  }
}

fn inner_param_to_transform() -> core.DesugarerTransform {
  n2t.one_to_one_nodemap_2_desugarer_transform(nodemap)
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(testing.AssertiveTestDataNoParam) {
  [
    // blank lines dropped, default `columns` filled in
    testing.data_no_param(
      source: "
        <> root
          <> ImageGrid
            <> GridImage
              src=figures/a.png
              <>
                '(a)'
            <> WriterlyBlankLine
            <> GridImage
              src=figures/b.png
              <>
                '(b)'
              <> WriterlyBlankLine
            <> WriterlyBlankLine
            <> GridCaption
              <>
                'Figure 1: two maps.'
      ",
      expected: "
        <> root
          <> ImageGrid
            columns=2
            <> GridImage
              src=figures/a.png
              <>
                '(a)'
            <> GridImage
              src=figures/b.png
              <>
                '(b)'
            <> GridCaption
              <>
                'Figure 1: two maps.'
      ",
    ),
    // explicit `columns`, gaps, `width` and `original` are kept (values
    // tidied); an unlabelled image and a grid without caption are fine
    testing.data_no_param(
      source: "
        <> root
          <> ImageGrid
            columns= 3
            column-gap= 6%
            row-gap=1.5em
            <> GridImage
              src=figures/a.png
              width= 78%
              original=figures/a.svg
            <> GridImage
              src=figures/b.png
              <>
                '(b)'
      ",
      expected: "
        <> root
          <> ImageGrid
            columns=3
            column-gap=6%
            row-gap=1.5em
            <> GridImage
              src=figures/a.png
              width=78%
              original=figures/a.svg
            <> GridImage
              src=figures/b.png
              <>
                '(b)'
      ",
    ),
  ]
}

pub fn assertive_tests() {
  testing.collection_no_param(name, assertive_tests_data(), constructor)
}
