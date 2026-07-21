import blame.{Src}
import desugaring as ds
import formatter_pipeline.{formatter_pipeline}
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string.{inspect as ins}
import infrastructure as infra
import on
import simplifile
import vxml.{type VXML, V}

const default_line_length = 55

const default_indentation_penalty = 0

type FragmentType {
  Root
  Chapter
  Section
  SubSection
  Exercises
  Unknown
}

type FragmentOf(z) =
  ds.OutputFragment(FragmentType, z)

fn fragment_bundler(
  vxml: VXML,
  classifier: FragmentType,
  input_dir_2_drop_from_blame_path_if_single_file: Option(String),
) -> FragmentOf(VXML) {
  let assert V(blame, _, _, _) = vxml
  let path = case blame {
    Src(_, path, _, _, _) -> path
    _ -> panic
  }
  let s = input_dir_2_drop_from_blame_path_if_single_file
  let path = case s {
    None -> path
    Some(name) -> {
      path |> infra.assert_drop_prefix("./" <> name <> "/")
    }
  }
  ds.OutputFragment(path: path, payload: vxml, classifier: classifier)
}

fn single_file_splitter(
  root: VXML,
  input_dir_name_only: String,
) -> Result(List(FragmentOf(VXML)), String) {
  Ok([fragment_bundler(root, Unknown, Some(input_dir_name_only))])
}

fn whole_book_splitter(root: VXML) -> Result(List(FragmentOf(VXML)), String) {
  let #(root, chapters) =
    infra.v_extract_children(root, infra.is_v_and_tag_equals(_, "Chapter"))

  // Exercises is optional: at most one, living in its own top-level file
  // (235A's exercises.wly) outside the chapter sequence. It must be extracted
  // like a chapter, else it stays in the root fragment and gets written back
  // into __parent.wly -- duplicating it, since exercises.wly is left in place.
  let #(root, exercises) =
    infra.v_extract_children(root, infra.is_v_and_tag_equals(_, "Exercises"))
  let exercises = list.map(exercises, fragment_bundler(_, Exercises, None))

  let root = fragment_bundler(root, Root, None)
  let #(chapters, sections, subsections) =
    chapters
    |> list.fold(#([], [], []), fn(acc, chapter) {
      let #(chapter, sections) =
        infra.v_extract_children(chapter, infra.is_v_and_tag_equals(
          _,
          "Section",
        ))
      let chapter_fragment = fragment_bundler(chapter, Chapter, None)

      let #(sections, subsections) =
        sections
        |> list.fold(#([], []), fn(acc_inner, section) {
          let #(section, subsections) =
            infra.v_extract_children(section, infra.is_v_and_tag_equals(
              _,
              "SubSection",
            ))
          let section_fragment = fragment_bundler(section, Section, None)
          let subsection_fragments =
            list.map(subsections, fragment_bundler(_, SubSection, None))
          #(
            [section_fragment, ..acc_inner.0],
            list.append(acc_inner.1, subsection_fragments),
          )
        })

      #(
        [chapter_fragment, ..acc.0],
        list.append(acc.1, sections),
        list.append(acc.2, subsections),
      )
    })

  list.flatten([
    [root],
    exercises,
    chapters,
    sections,
    subsections,
  ])
  |> Ok
}

fn extract_files(
  fmt_args: List(String),
) -> Result(#(List(String), List(String)), String) {
  case fmt_args {
    [] -> Ok(#([], []))
    ["-f" as first, ..rest] | ["-file" as first, ..rest] -> {
      case rest {
        [] -> Error("missing filename after '" <> first <> "'")
        [second, ..rest] -> {
          use #(ze_files, other_args) <- on.ok(extract_files(rest))
          Ok(#([second, ..ze_files], other_args))
        }
      }
    }
    [first, ..rest] -> {
      use #(ze_files, other_args) <- on.ok(extract_files(rest))
      Ok(#(ze_files, [first, ..other_args]))
    }
  }
}

fn extract_line_length_and_indentation_penalty(
  fmt_args: List(String),
) -> Result(#(Int, Int), String) {
  case fmt_args {
    [first, ..rest] ->
      case int.parse(first) {
        Ok(val) ->
          case rest {
            [] -> Ok(#(int.max(val, 40), default_indentation_penalty))
            [second, ..] ->
              case int.parse(second) {
                Ok(val2) ->
                  Ok(#(int.max(val, 40), int.min(int.max(val2, 0), 4)))
                Error(_) ->
                  Error(
                    "cannot parse '"
                    <> second
                    <> "' as an integer value for indentation penalty",
                  )
              }
          }
        Error(_) ->
          Error(
            "cannot parse '" <> first <> "' as an integer value for line length",
          )
      }
    _ -> Ok(#(default_line_length, default_indentation_penalty))
  }
}

pub fn render(amendments: ds.CommandLineAmendments, course_dir: String) -> Nil {
  let assert Ok(fmt_args) = dict.get(amendments.user_args, "--fmt")

  use #(files, fmt_args) <- on.error_ok(extract_files(fmt_args), fn(msg) {
    io.println(msg)
  })

  use #(line_length, indentation_penalty) <- on.error_ok(
    extract_line_length_and_indentation_penalty(fmt_args),
    fn(msg) { io.println(msg) },
  )

  let pipeline = formatter_pipeline(line_length, indentation_penalty)

  let #(output_dir_local_path, amendments) = case amendments.output_dir {
    None -> #("wly", amendments)
    Some(x) -> #(x, ds.CommandLineAmendments(..amendments, output_dir: None))
  }

  let assert None = amendments.input_dir
  let assert None = amendments.output_dir

  let parameters =
    ds.RendererParameters(
      input_dir: "./" <> course_dir <> "/wly/",
      output_dir: "./" <> course_dir <> "/" <> output_dir_local_path,
      prettifier_behavior: ds.PrettifierOff,
    )
    |> ds.amend_renderer_paramaters_by_command_line_amendments(amendments)

  let input_dir = parameters.input_dir
  let input_dir_name_only = case input_dir {
    "./" <> x -> x |> infra.drop_suffix("/")
    "/" <> x -> x |> infra.drop_suffix("/")
    x -> x |> infra.drop_suffix("/")
  }

  let files =
    list.map(files, fn(f) {
      let f =
        f
        |> infra.drop_prefix(input_dir_name_only)
        |> infra.drop_prefix("./" <> input_dir_name_only)
      case input_dir_name_only {
        "" -> f |> infra.ensure_prefix("./")
        _ -> f |> infra.ensure_prefix("/")
      }
    })
  let options =
    ds.vanilla_options()
    |> ds.amend_renderer_options_by_command_line_amendments(amendments)

  let renderer =
    ds.Renderer(
      assembler: ds.default_writerly_assembler(_, options),
      parser: ds.default_writerly_parser,
      pipeline: pipeline,
      splitter: case files {
        [] -> whole_book_splitter
        _ -> single_file_splitter(_, input_dir_name_only)
      },
      emitter: ds.default_writerly_emitter,
      writer: ds.default_writer,
      prettifier: ds.default_prettier_prettifier,
      filterer: ds.default_filterer(_, options, []),
    )
    |> ds.amend_renderer_by_command_line_amendments(amendments)

  let _ = simplifile.delete(parameters.output_dir <> "/*")

  list.each(
    case files {
      [] -> [""]
      _ -> files
    },
    fn(f) {
      io.println("")
      let parameters =
        ds.RendererParameters(
          ..parameters,
          input_dir: parameters.input_dir <> f,
        )
      case ds.run_renderer(renderer, parameters, options) {
        Error(error) -> io.println("\nrenderer error: " <> ins(error) <> "\n")
        _ -> Nil
      }
    },
  )
}
