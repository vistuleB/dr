import argv
import desugaring/testing
import gleam/io
import local_desugarers

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
