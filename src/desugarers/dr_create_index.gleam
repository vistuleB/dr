import desugaring/authoring
import desugaring/core.{
  type Desugarer, type DesugaringError, type TrafficLight, Continue, GoBack,
}
import desugaring/nodemaps_2_transform as n2t
import gleam/list
import gleam/option.{type Option}
import gleam/string.{inspect as ins}
import on
import vxml.{type VXML, Attr, Line, T, V}
import vxml/blame.{type Blame} as bl

pub const name = "dr_create_index"

// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️
// 🏖️🏖️ Desugarer 🏖️🏖️
// 🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️🏖️️️️️🏖️

/// Prepends a generated course index to the document.
pub fn constructor() -> Desugarer {
  authoring.no_param_desugarer(
    name: name,
    transform: inner_param_to_transform(),
  )
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 header 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn get(root: VXML, key: String) -> Option(#(Blame, String)) {
  core.v_first_attr_with_key(root, key)
  |> option.map(fn(attr) {
    #(attr.blame |> bl.advance(string.length(key) + 1), attr.val)
  })
}

fn header(root: VXML) -> VXML {
  let b = authoring.blame(name, 39)
  let title = get(root, "title") |> option.unwrap(#(b, "no title"))
  let course = get(root, "course") |> option.unwrap(#(b, "no course"))
  let term = get(root, "term") |> option.unwrap(#(b, "no term"))
  let lecturer = get(root, "lecturer") |> option.unwrap(#(b, "no lecturer"))
  let department = get(root, "department") |> option.unwrap(#(b, "department"))
  let institution =
    get(root, "institution") |> option.unwrap(#(b, "no institution"))
  V(
    b,
    "header",
    [
      Attr(b, "class", "index__header"),
    ],
    [
      V(
        b,
        "h1",
        [
          Attr(b, "class", "index__header__title"),
        ],
        [
          T(b, [Line(title.0, title.1)]),
        ],
      ),
      V(
        b,
        "div",
        [
          Attr(b, "class", "index__header__sectiontitle"),
        ],
        [
          T(b, [Line(course.0, course.1 <> ","), Line(term.0, term.1)]),
          V(b, "br", [], []),
          T(b, [
            Line(lecturer.0, lecturer.1 <> ","),
            Line(department.0, department.1 <> ","),
            Line(institution.0, institution.1),
          ]),
        ],
      ),
    ],
  )
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 gathering for table of contents~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

type Title =
  List(VXML)

type SubSectionInfo {
  SubSectionInfo(title: Title)
}

type SectionInfo {
  SectionInfo(title: Title, subsections: List(SubSectionInfo))
}

type ChapterInfo {
  ChapterInfo(title: Title, has_content: Bool, sections: List(SectionInfo))
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

type ChapterOrSection {
  Chapter
  Section
  SubSection
}

fn gather_title(
  vxml: VXML,
  chapter_or_section: ChapterOrSection,
) -> Result(Title, DesugaringError) {
  let title_tag = case chapter_or_section {
    Chapter -> "ChapterTitle"
    Section -> "SectionTitle"
    SubSection -> "SubSectionTitle"
  }
  use title_element <- on.ok(core.v_unique_child(vxml, title_tag))
  let assert V(_, _, _, children) = title_element
  // so that we can stomach both the cases where the
  // title has already been wrapped in <p></p> or not:
  case children {
    [V(_, "p", _, children)] -> Ok(children)
    _ -> Ok(children)
  }
}

fn add_chapter_to_state(
  state: List(ChapterInfo),
  title: Title,
  has_content: Bool,
) -> List(ChapterInfo) {
  [ChapterInfo(title, has_content, []), ..state]
}

fn add_section_with_title_to_state(
  state: List(ChapterInfo),
  title: Title,
) -> List(ChapterInfo) {
  let assert [ChapterInfo(_, _, sections) as first, ..rest] = state
  let first =
    ChapterInfo(..first, sections: [SectionInfo(title, []), ..sections])
  [first, ..rest]
}

fn add_subsection_with_title_to_state(
  state: List(ChapterInfo),
  title: Title,
) -> List(ChapterInfo) {
  let assert [
    ChapterInfo(_, _, [SectionInfo(_, subsections) as section, ..sections]) as chapter,
    ..rest
  ] = state
  let section =
    SectionInfo(..section, subsections: [SubSectionInfo(title), ..subsections])
  let chapter = ChapterInfo(..chapter, sections: [section, ..sections])
  [chapter, ..rest]
}

fn chapter_info_information_collector(
  vxml: VXML,
  state: List(ChapterInfo),
) -> Result(#(List(ChapterInfo), TrafficLight), DesugaringError) {
  case vxml {
    V(_, "Document", _, _) -> Ok(#(state, Continue))

    V(_, "Chapter", _, _) -> {
      let title = case gather_title(vxml, Chapter) {
        Ok(t) -> t
        Error(_) -> []
      }
      let has_content = chapter_has_content(vxml)
      Ok(#(state |> add_chapter_to_state(title, has_content), Continue))
    }

    V(_, "Section", _, _) -> {
      use title <- on.ok(gather_title(vxml, Section))
      Ok(#(state |> add_section_with_title_to_state(title), Continue))
    }

    V(_, "SubSection", _, _) -> {
      use title <- on.ok(gather_title(vxml, SubSection))
      Ok(#(state |> add_subsection_with_title_to_state(title), GoBack))
    }

    _ -> Ok(#(state, GoBack))
  }
}

fn gather_chapter_infos(
  root: VXML,
) -> Result(List(ChapterInfo), DesugaringError) {
  n2t.early_return_stateful_visit(root, [], chapter_info_information_collector)
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 table of contents~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn href(chapter_no: Int, section_no: Int, subsection_no: Int) -> String {
  case subsection_no {
    0 -> "./" <> ins(chapter_no) <> "-" <> ins(section_no) <> ".html"
    _ ->
      "./"
      <> ins(chapter_no)
      <> "-"
      <> ins(section_no)
      <> "-"
      <> ins(subsection_no)
      <> ".html"
  }
}

fn subsection_item(
  ch_no: Int,
  section_no: Int,
  subsection_no: Int,
  subsection: SubSectionInfo,
) -> VXML {
  let b = authoring.blame(name, 233)
  let SubSectionInfo(title) = subsection

  V(b, "li", [], [
    V(
      b,
      "a",
      [
        Attr(b, "href", href(ch_no, section_no, subsection_no)),
      ],
      title,
    ),
  ])
}

fn section_item(ch_no: Int, section_no: Int, section: SectionInfo) -> VXML {
  let b = authoring.blame(name, 249)
  let SectionInfo(title, subsections) = section
  let subsections_ol = case subsections {
    [] -> []
    _ -> [
      V(
        b,
        "ol",
        [],
        list.index_map(subsections |> list.reverse, fn(subsection, i) {
          subsection_item(ch_no, section_no, i + 1, subsection)
        }),
      ),
    ]
  }

  V(b, "li", [], [
    V(
      b,
      "a",
      [
        Attr(b, "href", href(ch_no, section_no, 0)),
      ],
      title,
    ),
    ..subsections_ol
  ])
}

fn chapter_item(ch_no: Int, chapter: ChapterInfo) -> VXML {
  let b = authoring.blame(name, 279)
  let ChapterInfo(title, has_content, sections) = chapter
  let sections_ol = case sections {
    [] -> []
    _ -> [
      V(
        b,
        "ol",
        [],
        list.index_map(sections |> list.reverse, fn(section, i) {
          section_item(ch_no, i + 1, section)
        }),
      ),
    ]
  }

  let heading = case has_content {
    True -> V(b, "a", [Attr(b, "href", href(ch_no, 0, 0))], title)
    False -> V(b, "span", [], title)
  }

  V(b, "li", [], [heading, ..sections_ol])
}

fn chapter_ol(chapters: List(ChapterInfo)) -> VXML {
  let b = authoring.blame(name, 304)
  V(
    b,
    "ol",
    [
      Attr(b, "class", "index__toc"),
    ],
    list.index_map(chapters |> list.reverse, fn(ch, i) {
      chapter_item(i + 1, ch)
    }),
  )
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 exercises link~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn gather_exercises_title_from_node(
  vxml: VXML,
) -> Result(Title, DesugaringError) {
  use title_element <- on.ok(core.v_unique_child(vxml, "ExercisesTitle"))
  let assert V(_, _, _, children) = title_element
  case children {
    [V(_, "p", _, children)] -> Ok(children)
    _ -> Ok(children)
  }
}

fn gather_exercises_title(root: VXML) -> option.Option(Title) {
  let assert V(_, "Document", _, children) = root
  case
    list.find(children, fn(v) {
      case v {
        V(_, "Exercises", _, _) -> True
        _ -> False
      }
    })
  {
    Error(_) -> option.None
    Ok(exercises) ->
      case gather_exercises_title_from_node(exercises) {
        Ok(t) -> option.Some(t)
        Error(_) -> option.None
      }
  }
}

fn exercises_link(root: VXML) -> option.Option(VXML) {
  let b = authoring.blame(name, 352)
  case gather_exercises_title(root) {
    option.None -> option.None
    option.Some(title) ->
      option.Some(
        V(b, "p", [Attr(b, "class", "index__exercises-link")], [
          V(b, "a", [Attr(b, "href", "./exercises.html")], title),
        ]),
      )
  }
}

// Bibliography link: same standalone-unit shape as the exercises link, but a
// plain TOC entry (class `index__standalone-link`) rather than the exercises
// pill styling.
fn gather_bibliography_title_from_node(
  vxml: VXML,
) -> Result(Title, DesugaringError) {
  use title_element <- on.ok(core.v_unique_child(vxml, "BibliographyTitle"))
  let assert V(_, _, _, children) = title_element
  case children {
    [V(_, "p", _, children)] -> Ok(children)
    _ -> Ok(children)
  }
}

fn gather_bibliography_title(root: VXML) -> option.Option(Title) {
  let assert V(_, "Document", _, children) = root
  case
    list.find(children, fn(v) {
      case v {
        V(_, "Bibliography", _, _) -> True
        _ -> False
      }
    })
  {
    Error(_) -> option.None
    Ok(bibliography) ->
      case gather_bibliography_title_from_node(bibliography) {
        Ok(t) -> option.Some(t)
        Error(_) -> option.None
      }
  }
}

fn bibliography_link(root: VXML) -> option.Option(VXML) {
  let b = authoring.blame(name, 398)
  case gather_bibliography_title(root) {
    option.None -> option.None
    option.Some(title) ->
      option.Some(
        V(b, "p", [Attr(b, "class", "index__standalone-link")], [
          V(b, "a", [Attr(b, "href", "./bibliography.html")], title),
        ]),
      )
  }
}

// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸
// 🌸 index navigation~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸🌸

fn anchor(id: String, href_val: String) -> VXML {
  let b = authoring.blame(name, 415)
  V(b, "a", [Attr(b, "id", id), Attr(b, "href", href_val)], [])
}

fn index_next_page_href(root: VXML) -> option.Option(String) {
  let assert V(_, "Document", _, children) = root
  case
    list.find(children, fn(v) {
      case v {
        V(_, "Chapter", _, _) -> True
        _ -> False
      }
    })
  {
    Error(_) -> option.None
    Ok(first_chapter) ->
      case chapter_has_content(first_chapter) {
        True -> option.Some(href(1, 0, 0))
        False -> option.Some(href(1, 1, 0))
      }
  }
}

// 🌸🌸🌸🌸🌸🌸🌸
// 🌸 main~~ 🌸
// 🌸🌸🌸🌸🌸🌸🌸

fn index(root: VXML) -> Result(VXML, DesugaringError) {
  use chapter_infos <- on.ok(gather_chapter_infos(root))
  let b = authoring.blame(name, 444)

  let nav = case index_next_page_href(root) {
    option.None -> []
    option.Some(next_href) -> [
      V(b, "Navigation", [Attr(b, "class", "nav")], [
        anchor("next-page", next_href),
      ]),
    ]
  }

  let exercises = case exercises_link(root) {
    option.None -> []
    option.Some(link) -> [link]
  }

  let bibliography = case bibliography_link(root) {
    option.None -> []
    option.Some(link) -> [link]
  }

  Ok(V(
    b,
    "Index",
    [
      Attr(authoring.blame(name, 469), "path", "./index.html"),
    ],
    list.flatten([
      nav,
      [header(root), chapter_ol(chapter_infos)],
      exercises,
      bibliography,
    ]),
  ))
}

fn at_root(root: VXML) -> Result(VXML, DesugaringError) {
  let assert V(_, "Document", _, children) = root
  use index <- on.ok(index(root))
  Ok(V(..root, children: [index, ..children]))
}

fn inner_param_to_transform() -> core.DesugarerTransform {
  at_root
  |> n2t.node_to_node_2_desugarer_transform_without_walking
}

// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊
// 🌊🌊🌊 tests 🌊🌊🌊🌊
// 🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊🌊

fn assertive_tests_data() -> List(core.AssertiveTestDataNoParam) {
  []
}

pub fn assertive_tests() {
  core.assertive_test_collection_from_data_no_param(
    name,
    assertive_tests_data(),
    constructor,
  )
}
