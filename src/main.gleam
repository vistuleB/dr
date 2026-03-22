import argv
import desugaring as ds
import formatter_renderer
import gleam/dict
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import infrastructure as infra
import on
import renderer
import simplifile

const ins = string.inspect

fn local_usage_message() {
  let margin = "   "
  io.println(margin <> "--fmt [<cols>] [<cols> <penalty>] [-file <name>]")
  io.println(margin <> "  -> (local option) run the formatter")
  io.println("")
  io.println(margin <> "     optional arguments:")
  io.println("")
  io.println(margin <> "     • <cols>: preferred line length")
  io.println(margin <> "     • <cols> <penalty>: preferred line")
  io.println(margin <> "       length and indentation penalty (number")
  io.println(margin <> "       of chars subtracted from line length at")
  io.println(margin <> "       each added level of indentation in the file)")
  io.println(margin <> "     • -file <name>: format only the given file")
  io.println("")
  io.println(margin <> "--local")
  io.println(margin <> "  -> include source-linking tooltips")
  io.println(margin <> "     server !)")
  io.println("")
  io.println("...and don't forget to include '--which <course dir>' in")
  io.println("order to specify which course you want to compile/run!")
  io.println("")
  io.println("                             ***")
  io.println("")
  io.println("Local server usage: use 'COURSE=<course dir> npm run dev' to")
  io.println("serve book on localhost:3003, or prefix 'PORT=xxxx' argument")
  io.println("to serve on  specific port! Enjoy!")
  io.println("")
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

  use _ <- on.stay(case args {
    ["--help"] | ["-help"] | ["-h"] -> {
      ds.basic_cli_usage("\n'gleam run' command line options (basic):")
      local_usage_message()
      on.Return(Nil)
    }

    ["--esoteric"] -> {
      ds.advanced_cli_usage("\n'gleam run' command line options (esoteric):")
      on.Return(Nil)
    }

    _ -> on.Stay(Nil)
  })

  use amendments <- on.stay(
    case
      ds.process_command_line_arguments(args, ["--fmt", "--local", "--which"])
    {
      Error(error) -> {
        io.println("")
        io.println("command line error: " <> ins(error))
        ds.basic_cli_usage("\ncommand line usage:")
        local_usage_message()
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

  case dict.get(amendments.user_args, "--fmt") {
    Ok(_) -> {
      io.println("")
      io.println("wly -> wly formatter")
      formatter_renderer.render(amendments, course_dir)
    }

    Error(_) -> {
      io.println("")
      io.println("wly -> html renderer")
      renderer.render(amendments, course_dir)
      io.println("")
    }
  }
}
