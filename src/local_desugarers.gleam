import desugarers/dr_create_index
import desugarers/dr_create_menu
import desugarers/dr_footnote_marker_to_sup_handle__outside
import desugarers/dr_generate_js_course
import desugaring/testing

pub const dr_create_index = dr_create_index.constructor

pub const dr_create_menu = dr_create_menu.constructor

pub const dr_footnote_marker_to_sup_handle__outside = dr_footnote_marker_to_sup_handle__outside.constructor

pub const dr_generate_js_course = dr_generate_js_course.constructor

pub const assertive_tests: List(fn() -> testing.AssertiveTestCollection) = [
  dr_create_index.assertive_tests,
  dr_create_menu.assertive_tests,
  dr_footnote_marker_to_sup_handle__outside.assertive_tests,
  dr_generate_js_course.assertive_tests,
]
