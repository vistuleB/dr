import blame.{Ext}
import desugaring as ds
import gleam/dict
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Regexp}
import gleam/result
import gleam/string.{inspect as ins}
import infrastructure as infra
import io_lines.{type OutputLine, OutputLine}
import pipeline
import simplifile
import vxml.{type VXML}
import writerly

pub type FragmentType {
  Chapter(Int)
  Section(Int, Int)
  SubSection(Int, Int, Int)
  Index
}

type Fragment(z) =
  ds.OutputFragment(FragmentType, z)

type OL =
  List(OutputLine)

pub type DRSplitterError {
  NoChapters
  MoreThanOneIndex
  NoIndex
}

type DocumentInfo {
  DocumentInfo(
    title: String,
    course: String,
    term: String,
    department: String,
    institution: String,
    lecturer: String,
    date: String,
    banner: String,
  )
}

fn index_error(e: infra.SingletonError) -> DRSplitterError {
  case e {
    infra.MoreThanOne -> MoreThanOneIndex
    infra.LessThanOne -> NoIndex
  }
}

fn our_splitter(root: VXML) -> Result(List(Fragment(VXML)), DRSplitterError) {
  use index <- result.try(
    infra.descendants_with_class(root, "index")
    |> infra.read_singleton
    |> result.map_error(index_error),
  )

  use chapters <- result.try(
    case infra.descendants_with_class(root, "chapter") {
      [] -> Error(NoChapters)
      chapters -> Ok(chapters)
    },
  )

  let #(chapters, list_list_sections) =
    chapters
    |> list.map(
      infra.v_extract_children(_, fn(child) {
        infra.is_v_and_has_class(child, "section")
      }),
    )
    |> list.unzip

  let #(list_list_sections, list_list_list_subsections) =
    list_list_sections
    |> list.map(fn(chapter_sections) {
      chapter_sections
      |> list.map(
        infra.v_extract_children(_, fn(child) {
          infra.is_v_and_has_class(child, "subsection")
        }),
      )
      |> list.unzip
    })
    |> list.unzip

  let chapter_fragments = {
    use chapter, chapter_idx <- list.index_map(chapters)
    let chapter_n = chapter_idx + 1
    let filename = string.inspect(chapter_n) <> "-0.html"
    ds.OutputFragment(Chapter(chapter_n), filename, chapter)
  }

  let section_fragments =
    {
      use chapter_sections, chapter_idx <- list.index_map(list_list_sections)
      let chapter_n = chapter_idx + 1
      use section, section_idx <- list.index_map(chapter_sections)
      let section_n = section_idx + 1
      let filename =
        [chapter_n, section_n]
        |> list.map(string.inspect)
        |> string.join("-")
        <> ".html"
      ds.OutputFragment(Section(chapter_n, section_n), filename, section)
    }
    |> list.flatten

  let subsection_fragments =
    {
      use chapter_subs, chapter_idx <- list.index_map(
        list_list_list_subsections,
      )
      let chapter_n = chapter_idx + 1
      use section_subs, section_idx <- list.index_map(chapter_subs)
      let section_n = section_idx + 1
      use subsection, subsection_idx <- list.index_map(section_subs)
      let subsection_n = subsection_idx + 1
      let filename =
        [chapter_n, section_n, subsection_n]
        |> list.map(string.inspect)
        |> string.join("-")
        <> ".html"
      ds.OutputFragment(
        SubSection(chapter_n, section_n, subsection_n),
        filename,
        subsection,
      )
    }
    |> list.flatten
    |> list.flatten

  list.flatten([
    [ds.OutputFragment(Index, "index.html", index)],
    chapter_fragments,
    section_fragments,
    subsection_fragments,
  ])
  |> Ok
}

// index emitter - handles index fragments
fn index_emitter(
  fragment: Fragment(VXML),
  offline_mathjax: Bool,
  document_info: DocumentInfo,
  author_mode: Bool,
) -> Result(Fragment(OL), String) {
  let blame = Ext([], "index_emitter")
  let lines =
    list.flatten([
      [
        OutputLine(blame, 0, "<!DOCTYPE html>"),
        OutputLine(blame, 0, "<html>"),
        OutputLine(blame, 0, "<head>"),
      ],
      document_meta_tags(blame, None, document_info),
      social_share_meta_tags(blame, None, document_info),
      [
        OutputLine(
          blame,
          2,
          "<link rel=\"stylesheet\" type=\"text/css\" href=\"app.css\" />",
        ),
      ],
      case author_mode {
        True -> [
          OutputLine(
            blame,
            2,
            "<link rel=\"stylesheet\" type=\"text/css\" href=\"local.css\" />",
          ),
        ]
        False -> []
      },
      [
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" src=\"mathjax_setup.js\"></script>",
        ),
        case offline_mathjax {
          True ->
            OutputLine(
              blame,
              2,
              "<script type=\"text/javascript\" src=\"tex-svg.js\"></script>",
            )
          False ->
            OutputLine(
              blame,
              2,
              "<script type=\"text/javascript\" src=\"https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-svg.min.js\"></script>",
            )
        },
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" src=\"app.js\"></script>",
        ),
        OutputLine(blame, 0, "</head>"),
        OutputLine(blame, 0, "<body>"),
      ],
      vxml.vxmls_to_html_output_lines(
        fragment.payload |> infra.v_get_children,
        2,
        2,
      ),
      [
        OutputLine(blame, 0, "</body>"),
        OutputLine(blame, 0, "</html>"),
        OutputLine(blame, 0, ""),
      ],
    ])
  Ok(ds.OutputFragment(..fragment, payload: lines))
}

// chapter emitter - handles chapter fragments
fn chapter_emitter(
  fragment: Fragment(VXML),
  offline_mathjax: Bool,
  document_info: DocumentInfo,
  author_mode: Bool,
) -> Result(Fragment(OL), String) {
  let assert Chapter(n) = fragment.classifier
  let blame = Ext([], "chapter_emitter")
  let chapter_title = "Chapter " <> string.inspect(n)

  let lines =
    list.flatten([
      [
        OutputLine(blame, 0, "<!DOCTYPE html>"),
        OutputLine(blame, 0, "<html>"),
        OutputLine(blame, 0, "<head>"),
      ],
      document_meta_tags(blame, Some(chapter_title), document_info),
      social_share_meta_tags(blame, Some(chapter_title), document_info),
      [
        OutputLine(
          blame,
          2,
          "<link rel=\"stylesheet\" type=\"text/css\" href=\"app.css\" />",
        ),
      ],
      case author_mode {
        True -> [
          OutputLine(
            blame,
            2,
            "<link rel=\"stylesheet\" type=\"text/css\" href=\"local.css\" />",
          ),
        ]
        False -> []
      },
      [
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" src=\"mathjax_setup.js\"></script>",
        ),
        case offline_mathjax {
          True ->
            OutputLine(
              blame,
              2,
              "<script type=\"text/javascript\" src=\"tex-svg.js\"></script>",
            )
          False ->
            OutputLine(
              blame,
              2,
              "<script type=\"text/javascript\" src=\"https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-svg.min.js\"></script>",
            )
        },
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" src=\"app.js\" defer></script>",
        ),
        OutputLine(blame, 0, "</head>"),
        OutputLine(blame, 0, "<body>"),
      ],
      vxml.vxmls_to_html_output_lines(
        fragment.payload |> infra.v_get_children,
        2,
        2,
      ),
      [
        OutputLine(blame, 0, "</body>"),
        OutputLine(blame, 0, "</html>"),
        OutputLine(blame, 0, ""),
      ],
    ])
  Ok(ds.OutputFragment(..fragment, payload: lines))
}

// section emitter - handles section fragments
fn section_emitter(
  fragment: Fragment(VXML),
  offline_mathjax: Bool,
  document_info: DocumentInfo,
  author_mode: Bool,
) -> Result(Fragment(OL), String) {
  let assert Section(chapter_n, section_n) = fragment.classifier
  let blame = Ext([], "section_emitter")
  let section_title =
    "Chapter " <> string.inspect(chapter_n) <> "." <> string.inspect(section_n)
  let lines =
    list.flatten([
      [
        OutputLine(blame, 0, "<!DOCTYPE html>"),
        OutputLine(blame, 0, "<html>"),
        OutputLine(blame, 0, "<head>"),
      ],
      document_meta_tags(blame, Some(section_title), document_info),
      social_share_meta_tags(blame, Some(section_title), document_info),
      [
        OutputLine(
          blame,
          2,
          "<link rel=\"stylesheet\" type=\"text/css\" href=\"app.css\" />",
        ),
      ],
      case author_mode {
        True -> [
          OutputLine(
            blame,
            2,
            "<link rel=\"stylesheet\" type=\"text/css\" href=\"local.css\" />",
          ),
        ]
        False -> []
      },
      [
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" src=\"mathjax_setup.js\"></script>",
        ),
        case offline_mathjax {
          True ->
            OutputLine(
              blame,
              2,
              "<script type=\"text/javascript\" src=\"tex-svg.js\"></script>",
            )
          False ->
            OutputLine(
              blame,
              2,
              "<script type=\"text/javascript\" src=\"https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-svg.min.js\"></script>",
            )
        },
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" src=\"app.js\" defer></script>",
        ),
        OutputLine(blame, 0, "</head>"),
        OutputLine(blame, 0, "<body>"),
      ],
      vxml.vxmls_to_html_output_lines(
        fragment.payload |> infra.v_get_children,
        2,
        2,
      ),
      [
        OutputLine(blame, 0, "</body>"),
        OutputLine(blame, 0, "</html>"),
        OutputLine(blame, 0, ""),
      ],
    ])
  Ok(ds.OutputFragment(..fragment, payload: lines))
}

// subsection emitter - handles subsection fragments
fn subsection_emitter(
  fragment: Fragment(VXML),
  offline_mathjax: Bool,
  document_info: DocumentInfo,
  author_mode: Bool,
) -> Result(Fragment(OL), String) {
  let assert SubSection(chapter_n, section_n, subsection_n) =
    fragment.classifier
  let blame = Ext([], "subsection_emitter")
  let subsection_title =
    "Chapter "
    <> string.inspect(chapter_n)
    <> "."
    <> string.inspect(section_n)
    <> "."
    <> string.inspect(subsection_n)
  let lines =
    list.flatten([
      [
        OutputLine(blame, 0, "<!DOCTYPE html>"),
        OutputLine(blame, 0, "<html>"),
        OutputLine(blame, 0, "<head>"),
      ],
      document_meta_tags(blame, Some(subsection_title), document_info),
      social_share_meta_tags(blame, Some(subsection_title), document_info),
      [
        OutputLine(
          blame,
          2,
          "<link rel=\"stylesheet\" type=\"text/css\" href=\"app.css\" />",
        ),
      ],
      case author_mode {
        True -> [
          OutputLine(
            blame,
            2,
            "<link rel=\"stylesheet\" type=\"text/css\" href=\"local.css\" />",
          ),
        ]
        False -> []
      },
      [
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" src=\"mathjax_setup.js\"></script>",
        ),
        case offline_mathjax {
          True ->
            OutputLine(
              blame,
              2,
              "<script type=\"text/javascript\" src=\"tex-svg.js\"></script>",
            )
          False ->
            OutputLine(
              blame,
              2,
              "<script type=\"text/javascript\" src=\"https://cdnjs.cloudflare.com/ajax/libs/mathjax/3.2.2/es5/tex-svg.min.js\"></script>",
            )
        },
        OutputLine(
          blame,
          2,
          "<script type=\"text/javascript\" src=\"app.js\" defer></script>",
        ),
        OutputLine(blame, 0, "</head>"),
        OutputLine(blame, 0, "<body>"),
      ],
      vxml.vxmls_to_html_output_lines(
        fragment.payload |> infra.v_get_children,
        2,
        2,
      ),
      [
        OutputLine(blame, 0, "</body>"),
        OutputLine(blame, 0, "</html>"),
        OutputLine(blame, 0, ""),
      ],
    ])
  Ok(ds.OutputFragment(..fragment, payload: lines))
}

fn document_meta_tags(
  blame: blame.Blame,
  title: Option(String),
  document_info: DocumentInfo,
) -> List(OutputLine) {
  [
    OutputLine(blame, 2, "<meta charset=\"utf-8\">"),
    OutputLine(
      blame,
      2,
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, minimum-scale=1\">",
    ),
    OutputLine(
      blame,
      2,
      "<title>" <> generate_title(document_info, title) <> "</title>",
    ),
    OutputLine(
      blame,
      2,
      "<meta name=\"description\" content=\""
        <> generate_description(document_info)
        <> "\">",
    ),
    // Author & publisher
    OutputLine(
      blame,
      2,
      "<meta name=\"author\" content=\"" <> document_info.lecturer <> "\">",
    ),
    OutputLine(
      blame,
      2,
      "<meta name=\"publisher\" content=\""
        <> generate_publisher(document_info)
        <> "\">",
    ),

    // Course / academic metadata
    OutputLine(
      blame,
      2,
      "<meta name=\"course\" content=\"" <> document_info.course <> "\">",
    ),
    OutputLine(
      blame,
      2,
      "<meta name=\"term\" content=\"" <> document_info.term <> "\">",
    ),
    OutputLine(
      blame,
      2,
      "<meta name=\"subject\" content=\"" <> document_info.title <> "\">",
    ),

    // Date
    OutputLine(
      blame,
      2,
      "<meta name=\"date\" content=\"" <> document_info.date <> "\">",
    ),
  ]
}

fn social_share_meta_tags(
  blame: blame.Blame,
  title: Option(String),
  document_info: DocumentInfo,
) -> List(OutputLine) {
  [
    // Open Graph
    OutputLine(
      blame,
      2,
      "<meta property=\"og:title\" content=\""
        <> generate_title(document_info, title)
        <> "\">",
    ),
    OutputLine(
      blame,
      2,
      "<meta property=\"og:description\" content=\""
        <> generate_description(document_info)
        <> "\">",
    ),
    OutputLine(blame, 2, "<meta property=\"og:type\" content=\"article\">"),
    OutputLine(
      blame,
      2,
      "<meta property=\"og:site_name\" content=\""
        <> document_info.department
        <> " | "
        <> document_info.institution
        <> "\">",
    ),
    OutputLine(blame, 2, "<meta property=\"og:locale\" content=\"en_US\">"),

    // Twitter card
    OutputLine(
      blame,
      2,
      "<meta name=\"twitter:card\" content=\"summary_large_image\">",
    ),
    OutputLine(
      blame,
      2,
      "<meta name=\"twitter:title\" content=\""
        <> generate_title(document_info, title)
        <> "\">",
    ),
    OutputLine(
      blame,
      2,
      "<meta property=\"twitter:description\" content=\""
        <> generate_description(document_info)
        <> "\">",
    ),
  ]
}

fn generate_description(document_info: DocumentInfo) -> String {
  document_info.title
  <> " for "
  <> document_info.course
  <> ", "
  <> document_info.term
  <> ", by "
  <> document_info.lecturer
  <> ", "
  <> document_info.department
  <> ", "
  <> document_info.institution
}

fn generate_title(
  document_info: DocumentInfo,
  chapter_or_section_title: Option(String),
) -> String {
  case chapter_or_section_title {
    None -> ""
    Some(x) -> x <> " of "
  }
  <> document_info.title
  <> " - "
  <> document_info.course
  <> " | "
  <> document_info.institution
}

fn generate_publisher(document_info: DocumentInfo) -> String {
  document_info.institution <> ", " <> document_info.department
}

// main emitter that dispatches to appropriate section-emitters
fn our_emitter(
  fragment: Fragment(VXML),
  offline_mathjax: Bool,
  document_info: DocumentInfo,
  author_mode: Bool,
) -> Result(Fragment(OL), String) {
  case fragment.classifier {
    Index ->
      index_emitter(fragment, offline_mathjax, document_info, author_mode)
    Chapter(_) ->
      chapter_emitter(fragment, offline_mathjax, document_info, author_mode)
    Section(_, _) ->
      section_emitter(fragment, offline_mathjax, document_info, author_mode)
    SubSection(_, _, _) ->
      subsection_emitter(fragment, offline_mathjax, document_info, author_mode)
  }
}

fn cleanup_html_files(output_dir: String) -> Result(Nil, String) {
  io.println("• rm " <> output_dir <> "/**.html")
  case simplifile.read_directory(output_dir) {
    Ok(files) -> {
      files
      |> list.filter(fn(file) { string.ends_with(file, ".html") })
      |> list.map(fn(file) {
        let file_path = output_dir <> "/" <> file
        case simplifile.delete(file_path) {
          Ok(_) -> Ok(Nil)
          Error(error) -> {
            io.println(
              "Warning: Could not delete "
              <> file_path
              <> ": "
              <> string.inspect(error),
            )
            Ok(Nil)
            // continue even if some files can't be deleted
          }
        }
      })
      |> result.all
      |> result.map(fn(_) { Nil })
    }
    Error(error) -> {
      io.println(
        "Warning: Could not read output directory "
        <> output_dir
        <> ": "
        <> string.inspect(error),
      )
      Ok(Nil)
      // continue even if directory can't be read
    }
  }
}

fn filename_shorthand_to_path_fragment(
  shorthand: String,
  filename_shorthand_regexp: Regexp,
) -> String {
  let zero_pad = fn(s) -> String {
    case string.length(s) < 2 {
      True -> "0" <> s
      False -> s
    }
  }
  case regexp.scan(filename_shorthand_regexp, shorthand) {
    [one] -> {
      case one.submatches {
        [Some(ch_no), Some(section_no), None] ->
          zero_pad(ch_no)
          <> "/"
          <> case zero_pad(section_no) {
            "00" -> "__parent.wly"
            x -> x
          }
        [Some(ch_no), Some(section_no), Some(subsection_no)] ->
          zero_pad(ch_no)
          <> "/"
          <> zero_pad(section_no)
          <> "/"
          <> zero_pad(subsection_no)
        _ -> shorthand
      }
    }
    _ -> shorthand
  }
}

fn expand_filename_shorthands_to_path_fragments(
  amendments: ds.CommandLineAmendments,
) -> ds.CommandLineAmendments {
  let assert Ok(filename_shorthand_regexp) =
    regexp.from_string(
      "^([1-9][\\d]{0,1})[\\.]([\\d]{1,2})(?:[\\.]([1-9][\\d]{0,1})){0,1}$",
    )

  let only_paths =
    list.map(amendments.only_paths, filename_shorthand_to_path_fragment(
      _,
      filename_shorthand_regexp,
    ))

  let only_key_values =
    list.map(amendments.only_key_values, fn(x) {
      let #(path, k, v) = x
      #(
        filename_shorthand_to_path_fragment(path, filename_shorthand_regexp),
        k,
        v,
      )
    })

  ds.CommandLineAmendments(
    ..amendments,
    only_paths: only_paths,
    only_key_values: only_key_values,
  )
}

pub fn render(amendments: ds.CommandLineAmendments, course_dir: String) -> Nil {
  let #(output_dir_local_path, amendments) = case amendments.output_dir {
    None -> #("public", amendments)
    Some(x) -> #(x, ds.CommandLineAmendments(..amendments, output_dir: None))
  }

  let assert None = amendments.input_dir
  let assert None = amendments.output_dir
  let parent = course_dir <> "/wly/__parent.wly"
  let assert Ok(contents) = simplifile.read(parent)
  let assert Ok([parsed_contents, ..]) = writerly.parse_string(contents, "")
  let parsed_contents = writerly.writerly_to_vxml(parsed_contents)
  let banner = case infra.v_first_attr_with_key(parsed_contents, "banner") {
    None ->
      panic as "__parent.wly did not specify the banner attribute (what should appear in the browser tab)"
    Some(x) -> x.val
  }
  io.println("author set banner to be " <> banner)
  let title = case infra.v_first_attr_with_key(parsed_contents, "title") {
    None -> panic as "__parent.wly did not specify any title attribute"
    Some(x) -> x.val
  }
  io.println("author set title to be " <> title)
  let course = case infra.v_first_attr_with_key(parsed_contents, "course") {
    None -> panic as "__parent.wly did not specify any course attribute"
    Some(x) -> x.val
  }
  io.println("author set course to be " <> course)
  let term = case infra.v_first_attr_with_key(parsed_contents, "term") {
    None -> panic as "__parent.wly did not specify any term attribute"
    Some(x) -> x.val
  }
  io.println("author set term to be " <> term)
  let department = case
    infra.v_first_attr_with_key(parsed_contents, "department")
  {
    None -> panic as "__parent.wly did not specify any department attribute"
    Some(x) -> x.val
  }
  io.println("author set department to be " <> department)
  let institution = case
    infra.v_first_attr_with_key(parsed_contents, "institution")
  {
    None -> panic as "__parent.wly did not specify any institution attribute"
    Some(x) -> x.val
  }
  io.println("author set institution to be " <> institution)
  let lecturer = case infra.v_first_attr_with_key(parsed_contents, "lecturer") {
    None -> panic as "__parent.wly did not specify any lecturer attribute"
    Some(x) -> x.val
  }
  io.println("author set lecturer to be " <> lecturer)
  let date = case infra.v_first_attr_with_key(parsed_contents, "date") {
    None -> panic as "__parent.wly did not specify any date attribute"
    Some(x) -> x.val
  }
  io.println("author set lecturer to be " <> date)
  let document_info =
    DocumentInfo(
      title: title,
      course: course,
      term: term,
      department: department,
      institution: institution,
      lecturer: lecturer,
      date: date,
      banner: banner,
    )

  let parameters =
    ds.RendererParameters(
      input_dir: "./" <> course_dir <> "/wly/",
      output_dir: "./" <> course_dir <> "/" <> output_dir_local_path <> "/",
      prettifier_behavior: ds.PrettifierOff,
    )
    |> ds.amend_renderer_paramaters_by_command_line_amendments(amendments)

  let author_mode = dict.has_key(amendments.user_args, "--local")
  let offline_mathjax = dict.has_key(amendments.user_args, "--offline-mathjax")
  let amendments = expand_filename_shorthands_to_path_fragments(amendments)

  let renderer =
    ds.Renderer(
      assembler: ds.default_writerly_assembler(amendments.only_paths),
      parser: ds.default_writerly_parser(amendments.only_key_values),
      pipeline: pipeline.pipeline(),
      splitter: our_splitter,
      emitter: our_emitter(_, offline_mathjax, document_info, author_mode),
      writer: ds.default_writer,
      prettifier: ds.default_prettier_prettifier,
    )
    |> ds.amend_renderer_by_command_line_amendments(amendments)

  let debug_options =
    ds.vanilla_options()
    |> ds.amend_renderer_options_by_command_line_amendments(amendments)

  // clean up HTML files before rendering
  case cleanup_html_files(parameters.output_dir) {
    Ok(_) -> Nil
    Error(error) -> io.println("HTML cleanup failed: " <> error)
  }

  case ds.run_renderer(renderer, parameters, debug_options) {
    Error(error) -> io.println("\nrenderer error: " <> ins(error) <> "\n")
    _ -> Nil
  }
}
