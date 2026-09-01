import argv
import gleam/io
import local_desugarers
import vxml_pipeline/testing

pub fn main() {
  io.println("")

  case
    testing.test_desugarers(
      local_desugarers.assertive_tests,
      argv.load().arguments,
    )
  {
    Ok(Nil) -> Nil
    Error(message) -> panic as message
  }
}
