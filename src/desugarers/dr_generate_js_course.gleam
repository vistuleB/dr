import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugarerTransform, type DesugaringError,
  type TrafficLight, Continue, DesugaringError, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/int
import gleam/list
import gleam/string
import on
import simplifile
import vxml.{type VXML, V}

pub const name = "dr_generate_js_course"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Writes `public/course.js` with a map describing whether
/// each chapter has direct content or begins with a section.
pub fn constructor(param: Param) -> Desugarer {
  authoring.desugarer(
    name: name,
    param: param,
    prepare: param_to_inner_param,
    transform: inner_param_to_transform,
  )
}

type Param =
  String

type InnerParam =
  String

fn param_to_inner_param(param: Param) -> Result(InnerParam, DesugaringError) {
  Ok(param |> core.drop_suffix("/") <> "/public")
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 chapter map collection 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

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

fn chapter_has_section(vxml: VXML) -> Bool {
  let assert V(_, "Chapter", _, children) = vxml
  list.any(children, fn(child) {
    case child {
      V(_, "Section", _, _) -> True
      _ -> False
    }
  })
}

// state: chapter values accumulated in reverse order (0 = chapter has content,
//        1 = chapter has no content but has a Section)
type State =
  List(Int)

fn chapter_collector(
  vxml: VXML,
  state: State,
) -> Result(#(State, TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) -> Ok(#(state, Continue))
    V(chapter_blame, "Chapter", _, _) -> {
      case chapter_has_content(vxml) {
        True -> Ok(#([0, ..state], GoBack))
        False ->
          case chapter_has_section(vxml) {
            True -> Ok(#([1, ..state], GoBack))
            False ->
              Error(DesugaringError(
                chapter_blame,
                "The chapter has either no content or section",
              ))
          }
      }
    }
    _ -> Ok(#(state, GoBack))
  }
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 JS content builder 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn build_course_js(chapter_values: List(Int)) -> String {
  let entries =
    list.index_map(chapter_values, fn(value, i) {
      "  " <> int.to_string(i + 1) <> ": " <> int.to_string(value) <> ","
    })
    |> string.join("\n")
  "const chapterMap = {\n" <> entries <> "\n};\n"
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 transform 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn at_root(root: VXML, inner: InnerParam) -> Result(Nil, DesugaringError) {
  use chapter_values_reversed <- on.ok(n2t.early_return_stateful_visit(
    root,
    [],
    chapter_collector,
  ))
  let content = build_course_js(list.reverse(chapter_values_reversed))
  let path = inner <> "/course.js"
  use error <- on.error(simplifile.write(path, content))
  Error(DesugaringError(
    authoring.blame(name, 122),
    "failed to write course.js to '"
      <> path
      <> "': "
      <> simplifile.describe_error(error),
  ))
}

fn inner_param_to_transform(inner: InnerParam) -> DesugarerTransform {
  at_root(_, inner)
  |> n2t.node_to_nil_2_desugarer_transform_without_walking()
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestData(Param)) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data(
    name,
    assertive_tests_data(),
    constructor,
  )
}
