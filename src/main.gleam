import argv
import formatter_renderer
import gleam/dict
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import latex_renderer
import local_desugarers
import on
import renderer
import simplifile
import vxml_pipeline as ds
import vxml_pipeline/core as infra

fn local_cli_usage() -> String {
  let margin = string.repeat(" ", ds.help_message_margin)
  [
    margin <> "--fmt [<cols>] [<cols> <penalty>] [-file <name>]",
    margin <> "  -> (local option) run the formatter",
    "",
    margin <> "     optional arguments:",
    "",
    margin <> "     • <cols>: preferred line length",
    margin <> "     • <cols> <penalty>: preferred line",
    margin <> "       length and indentation penalty (number",
    margin <> "       of chars subtracted from line length at",
    margin <> "       each added level of indentation in the file)",
    margin <> "     • -file <name>: format only the given file",
    "",
    margin <> "--latex-monolithic",
    margin <> "  -> (local option) render wly -> a single self-contained",
    margin <> "     LaTeX file <course dir>/latex/main.tex, compilable",
    margin <> "     with pdflatex (clickable TOC + PDF outline)",
    "",
    margin <> "--latex-chapters / --latex-sections / --latex-subsections",
    margin <> "  -> modular LaTeX: a main.tex (title + TOC) that \\inputs",
    margin <> "     one file per chapter (and, at finer granularities, per",
    margin <> "     section / subsection) + one per standalone unit; compile",
    margin <> "     <course dir>/latex/main.tex",
    "",
    margin <> "--local",
    margin <> "  -> include source-linking tooltips",
    margin <> "     server !)",
    "",
    margin <> "--offline-mathjax",
    margin <> "  -> use local mathjax library instead of CDN url",
    "",
    "...and don't forget to include '--which <course dir>' in",
    "order to specify which course you want to compile/run!",
    "",
    "                             ***",
    "",
    "Local server usage: use 'COURSE=<course dir> npm run dev' to",
    "serve book on localhost:3003, or prefix 'PORT=xxxx' argument",
    "to serve on  specific port! Enjoy!",
    "",
  ]
  |> string.join("\n")
}

// Which LaTeX-output flag (if any) was passed, and at what modularity.
// `--latex-monolithic` is the monolithic single-file mode. Finer flags win over coarser
// ones if several are given.
fn latex_granularity(
  user_args: dict.Dict(String, List(String)),
) -> option.Option(latex_renderer.Granularity) {
  let has = fn(flag) { dict.has_key(user_args, flag) }
  case
    has("--latex-subsections"),
    has("--latex-sections"),
    has("--latex-chapters"),
    has("--latex-monolithic")
  {
    True, _, _, _ -> option.Some(latex_renderer.BySubSection)
    _, True, _, _ -> option.Some(latex_renderer.BySection)
    _, _, True, _ -> option.Some(latex_renderer.ByChapter)
    _, _, _, True -> option.Some(latex_renderer.Monolithic)
    _, _, _, _ -> option.None
  }
}

fn handle_formatting_request(
  arguments: ds.ParsedCLIArguments,
  course_dir: String,
) -> Result(Bool, ds.CLIError) {
  case
    dict.get(arguments.user_args, "--fmt"),
    latex_granularity(arguments.user_args)
  {
    Ok(_), _ -> {
      io.println("wly -> wly formatter")
      use _ <- on.ok(
        formatter_renderer.render(arguments, course_dir)
        |> result.map_error(ds.ClientSideError),
      )
      Ok(True)
    }

    _, option.Some(granularity) -> {
      io.println("wly -> latex renderer")
      latex_renderer.render(arguments, course_dir, granularity)
      Ok(True)
    }

    Error(_), option.None -> Ok(False)
  }
}

fn handle_cli_error(error: ds.CLIError) -> Nil {
  io.println("command line error: " <> ds.cli_error_message(error))
  io.println("")
}

pub fn main() {
  io.println("")

  let args =
    argv.load().arguments
    |> list.map(fn(x) {
      case x {
        "only" -> "--only"
        "which" -> "--which"
        _ -> x
      }
    })

  use args <- on.error_ok(ds.read_from_dot_last_command(args), handle_cli_error)

  use arguments <- on.error_ok(
    ds.process_command_line_arguments(args, [
      "--fmt",
      "--latex-monolithic",
      "--latex-chapters",
      "--latex-sections",
      "--latex-subsections",
      "--local",
      "--which",
      "--offline-mathjax",
    ]),
    handle_cli_error,
  )

  use help_requested <- on.error_ok(
    ds.handle_help_requests(arguments, local_cli_usage),
    handle_cli_error,
  )

  use maintenance_requested <- on.error_ok(
    ds.handle_maintenance_requests(arguments, local_desugarers.assertive_tests),
    handle_cli_error,
  )

  use _ <- on.stay(case maintenance_requested || help_requested {
    True -> on.Return(Nil)
    False -> on.Stay(Nil)
  })

  use course_dir <- on.stay(case dict.get(arguments.user_args, "--which") {
    Ok([name]) -> {
      let name = name |> infra.drop_ending_slash |> infra.drop_prefix("./")
      case simplifile.is_directory(name <> "/wly") {
        Ok(_) -> {
          on.Stay(name)
        }
        _ -> {
          io.println(
            "expecting '"
            <> name
            <> "' to be a local directory with subdirectory 'wly'; crashing out",
          )
          io.println("")
          on.Return(Nil)
        }
      }
    }

    _ -> {
      io.println(
        "use '--which' option to specify a project_dir name pls (without spaces); crashing out",
      )
      io.println("")
      on.Return(Nil)
    }
  })

  use _ <- on.stay(case arguments.input_dir {
    option.Some(_) -> {
      io.println(
        "unexpected --input-dir argument; use '--which' to specify a local project directory; crashing out",
      )
      io.println("")
      on.Return(Nil)
    }
    _ -> on.Stay(Nil)
  })

  use formatting_requested <- on.error_ok(
    handle_formatting_request(arguments, course_dir),
    handle_cli_error,
  )

  use _ <- on.stay(case formatting_requested {
    True -> on.Return(Nil)
    False -> on.Stay(Nil)
  })

  use _ <- on.error_ok(ds.write_to_dot_last_command(args), handle_cli_error)

  io.println("wly -> html renderer")
  renderer.render(arguments, course_dir)
}
