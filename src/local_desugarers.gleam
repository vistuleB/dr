import desugarers/dr_create_index
import desugarers/dr_create_menu
import desugarers/dr_footnote_marker_to_sup_handle__outside
import desugarers/dr_generate_js_course
import desugarers/dr_image_grids_to_html
import desugarers/dr_insert_cover_image
import desugarers/dr_latex_collect_document_context
import desugarers/dr_normalize_image_grids
import vxml_pipeline/testing

pub const dr_create_index = dr_create_index.constructor

pub const dr_create_menu = dr_create_menu.constructor

pub const dr_insert_cover_image = dr_insert_cover_image.constructor

pub const dr_footnote_marker_to_sup_handle__outside = dr_footnote_marker_to_sup_handle__outside.constructor

pub const dr_generate_js_course = dr_generate_js_course.constructor

pub const dr_latex_collect_document_context = dr_latex_collect_document_context.constructor

pub const dr_normalize_image_grids = dr_normalize_image_grids.constructor

pub const dr_image_grids_to_html = dr_image_grids_to_html.constructor

pub const assertive_tests: List(fn() -> testing.AssertiveTestCollection) = [
  dr_create_index.assertive_tests,
  dr_create_menu.assertive_tests,
  dr_footnote_marker_to_sup_handle__outside.assertive_tests,
  dr_generate_js_course.assertive_tests,
  dr_image_grids_to_html.assertive_tests,
  dr_insert_cover_image.assertive_tests,
  dr_latex_collect_document_context.assertive_tests,
  dr_normalize_image_grids.assertive_tests,
]
