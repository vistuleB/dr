import argv
import desugaring as ds
import desugaring/core as infra
import formatter_renderer
import gleam/dict
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import latex_renderer
import local_desugarers
import on
import renderer
import simplifile

const ins = string.inspect

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
    margin <> "--last-command",
    margin <> "  -> run the same arguments as the previous command (from local",
    margin <> "     .last-command file)",
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

pub fn main() {
  let args =
    argv.load().arguments
    |> list.map(fn(x) {
      case x {
        "only" -> "--only"
        "which" -> "--which"
        _ -> x
      }
    })

  let #(args, use_last_command) = case list.contains(args, "--last-command") {
    True -> {
      let args = list.filter(args, fn(s) { s != "--last-command" })
      #(args, True)
    }
    False -> #(args, False)
  }

  assert !list.contains(args, "--last-command")

  let args = case use_last_command {
    True ->
      case simplifile.read(".last-command") {
        Ok(contents) -> {
          string.split(contents, " ")
          |> list.map(string.trim)
          |> list.filter(fn(s) { !string.is_empty(s) })
          |> list.append(args)
        }
        Error(_) -> panic as "unable to find '.last-command'"
      }
    False -> args
  }

  let #(args, help_requested) = ds.handle_help_requests(args, local_cli_usage)
  use _ <- on.stay(case help_requested {
    True -> on.Return(Nil)
    False -> on.Stay(Nil)
  })

  use #(args, maintenance_requested) <- on.error_ok(
    ds.handle_maintenance_requests(args, local_desugarers.assertive_tests),
    fn(error) {
      io.println("maintenance error: " <> error)
      io.println("")
    },
  )
  use _ <- on.stay(case maintenance_requested {
    True -> on.Return(Nil)
    False -> on.Stay(Nil)
  })

  let args_string = string.join(args, " ")

  use amendments <- on.stay(
    case
      ds.process_command_line_arguments(args, [
        "--fmt",
        "--latex-monolithic",
        "--latex-chapters",
        "--latex-sections",
        "--latex-subsections",
        "--local",
        "--which",
        "--offline-mathjax",
      ])
    {
      Error(error) -> {
        io.println("")
        io.println("command line error: " <> ins(error))
        ds.basic_cli_usage("\ncommand line usage:")
        local_cli_usage() |> io.print
        on.Return(Nil)
      }

      Ok(amendments) -> {
        on.Stay(amendments)
      }
    },
  )

  use course_dir <- on.stay(case dict.get(amendments.user_args, "--which") {
    Ok([name]) -> {
      let name = name |> infra.drop_ending_slash |> infra.drop_prefix("./")
      case simplifile.is_directory(name <> "/wly") {
        Ok(_) -> {
          on.Stay(name)
        }
        _ -> {
          io.println(
            "\nexpecting '"
            <> name
            <> "' to be a local directory with subdirectory 'wly'; crashing out",
          )
          on.Return(Nil)
        }
      }
    }
    _ -> {
      io.println(
        "\nuse '--which' option to specify a project_dir name pls (without spaces); crashing out\n",
      )
      on.Return(Nil)
    }
  })

  use _ <- on.stay(case amendments.input_dir {
    option.Some(_) -> {
      io.println(
        "\nunexpected --input-dir argument; use '--which' to specify a local project directory; crashing out\n",
      )
      on.Return(Nil)
    }
    _ -> on.Stay(Nil)
  })

  case
    dict.get(amendments.user_args, "--fmt"),
    latex_granularity(amendments.user_args)
  {
    Ok(_), _ -> {
      io.println("")
      io.println("wly -> wly formatter")
      formatter_renderer.render(amendments, course_dir)
    }

    _, option.Some(granularity) -> {
      io.println("")
      io.println("wly -> latex renderer")
      latex_renderer.render(amendments, course_dir, granularity)
      io.println("")
    }

    Error(_), option.None -> {
      io.println("")
      io.println("wly -> html renderer")
      renderer.render(amendments, course_dir)
      io.println("")
    }
  }

  case simplifile.write(".last-command", args_string) {
    Ok(_) -> Nil
    _ -> io.println("Warning: unable to write args_string to .last-command")
  }
}
