import desugaring as ds
import desugaring/core as infra
import desugaring/writerly_defaults as wd
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Regexp}
import gleam/string.{inspect as ins}
import latex_pipeline
import simplifile
import vxml.{type Attr, type VXML, Attr, T, V}
import vxml/blame.{Ext}
import vxml/io_lines.{type OutputLine, OutputLine}
import writerly

// ============================================================================
// Writerly -> LaTeX renderer
//
// Emits ONE self-contained `.tex` file (report class) that compiles with
// `pdflatex`. Structure maps onto native sectioning (`\chapter`/`\section`/
// `\subsection`), theorem-like blocks onto shared-counter `\newtheorem`
// environments, proofs onto amsthm's `proof`, and math passes through verbatim.
// `hyperref` turns `\tableofcontents` into a clickable TOC and produces the PDF
// bookmark outline automatically. Cross-references (`>>handle`, `name##<<`) are
// rewritten to `\ref{}`/`\label{}`; footnote markers to `\footnote{}`.
// ============================================================================

type DocumentInfo {
  DocumentInfo(
    title: String,
    course: String,
    term: String,
    department: String,
    institution: String,
    lecturer: String,
    date: String,
  )
}

// Regex tokens recognized inside running text.
//   (*>>name)   footnote reference marker
//   >>name      cross-reference           -> \ref{name}
//   name##<<    equation/label definition -> \label{name}
// The name charset is exactly what Writerly handles use (letters, digits, `_`,
// `:`, `-`). It deliberately excludes `.` so a ref at a sentence end, `>>thm-x.`,
// does not swallow the trailing period into the label name.
const token_pattern = "\\(\\*>>[A-Za-z][A-Za-z0-9_:-]*\\)|>>[A-Za-z][A-Za-z0-9_:-]*|[A-Za-z][A-Za-z0-9_:-]*##<<"

// Inside math we only rewrite refs and labels (never footnotes, never escape).
const math_token_pattern = ">>[A-Za-z][A-Za-z0-9_:-]*|[A-Za-z][A-Za-z0-9_:-]*##<<"

// Emit context threaded through the tree walk.
type Ctx {
  Ctx(footnotes: Dict(String, String), tok: Regexp, math_tok: Regexp)
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

fn find_attr(attrs: List(Attr), key: String) -> Option(String) {
  attrs
  |> list.find_map(fn(a) {
    case a {
      Attr(_, k, v) if k == key -> Ok(v)
      _ -> Error(Nil)
    }
  })
  |> option.from_result
}

fn gather_text(vxml: VXML) -> String {
  case vxml {
    T(_, lines) -> lines |> list.map(fn(l) { l.content }) |> string.join("\n")
    V(_, _, _, children) -> children |> list.map(gather_text) |> string.concat
  }
}

// Escape the LaTeX-fatal characters in a chunk of prose. `\`, `{`, `}`, `$` and
// `~` are deliberately left alone: by the time prose reaches here, math has been
// pulled into `Math` nodes and `_`/`*` emphasis into `<i>`/`<b>`, so a surviving
// `\` or `$` is an intentional literal (e.g. `\$`) that is already valid LaTeX.
fn escape_prose(s: String) -> String {
  s
  |> string.replace("#", "\\#")
  |> string.replace("%", "\\%")
  |> string.replace("&", "\\&")
  |> string.replace("_", "\\_")
  |> string.replace("^", "\\textasciicircum{}")
}

// A raw attribute value (chapter/section title, theorem note) may interleave
// prose and `$math$` because attribute strings are never math-parsed. Escape the
// prose runs, keep the math runs verbatim.
fn emit_mixed(s: String) -> String {
  string.split(s, "$")
  |> list.index_map(fn(seg, i) {
    case int.is_even(i) {
      True -> escape_prose(seg)
      False -> "$" <> seg <> "$"
    }
  })
  |> string.concat
}

fn strip_trailing_period(s: String) -> String {
  case string.ends_with(s, ".") {
    True -> string.drop_end(s, 1)
    False -> s
  }
}

// ---------------------------------------------------------------------------
// In-text token rewriting
// ---------------------------------------------------------------------------

// Prose: rewrite footnote/ref/label tokens and escape everything in between.
fn transform_prose(s: String, ctx: Ctx) -> String {
  case regexp.scan(ctx.tok, s) {
    [] -> escape_prose(s)
    [m, ..] ->
      case string.split_once(s, m.content) {
        Ok(#(before, after)) ->
          escape_prose(before)
          <> prose_token_to_latex(m.content, ctx)
          <> transform_prose(after, ctx)
        Error(_) -> escape_prose(s)
      }
  }
}

fn prose_token_to_latex(token: String, ctx: Ctx) -> String {
  case string.starts_with(token, "(*>>") {
    True -> {
      // strip leading "(*>>" and trailing ")"
      let name = token |> string.drop_start(4) |> string.drop_end(1)
      case dict.get(ctx.footnotes, name) {
        Ok(content) -> "\\footnote{" <> content <> "}"
        Error(_) -> ""
      }
    }
    False ->
      case string.starts_with(token, ">>") {
        True -> "\\ref{" <> string.drop_start(token, 2) <> "}"
        False -> "\\label{" <> string.drop_end(token, 4) <> "}"
      }
  }
}

// Math: rewrite refs/labels only, no escaping.
fn transform_math(s: String, ctx: Ctx) -> String {
  case regexp.scan(ctx.math_tok, s) {
    [] -> s
    [m, ..] ->
      case string.split_once(s, m.content) {
        Ok(#(before, after)) ->
          before <> math_token_to_latex(m.content) <> transform_math(after, ctx)
        Error(_) -> s
      }
  }
}

fn math_token_to_latex(token: String) -> String {
  case string.starts_with(token, ">>") {
    True -> "\\ref{" <> string.drop_start(token, 2) <> "}"
    False -> "\\label{" <> string.drop_end(token, 4) <> "}"
  }
}

// ---------------------------------------------------------------------------
// Math block emission
// ---------------------------------------------------------------------------

// Strip the `$$` produced-delimiters the pipeline wrapped around a MathBlock.
fn strip_display_delims(s: String) -> String {
  let s = string.trim(s)
  let s = case string.starts_with(s, "$$") {
    True -> string.drop_start(s, 2)
    False -> s
  }
  let s = case string.ends_with(s, "$$") {
    True -> string.drop_end(s, 2)
    False -> s
  }
  string.trim(s)
}

// Standalone display environments create their own display math and must be
// emitted bare; anything else is wrapped in `\[ ... \]`. (Subsidiary envs like
// `cases`/`array`/`aligned` are not in this list and ride inside the `\[ \]`.)
fn is_standalone_env(inner: String) -> Bool {
  let envs = [
    "equation*", "equation", "align*", "align", "alignat*", "alignat",
    "flalign*", "flalign", "gather*", "gather", "multline*", "multline",
    "eqnarray*", "eqnarray",
  ]
  list.any(envs, fn(e) { string.starts_with(inner, "\\begin{" <> e <> "}") })
}

// A referenced equation carries a `\label` (from a `name##<<` marker). LaTeX can
// only attach a label to a *numbered* line, but the Writerly source routinely
// puts such equations inside a starred (unnumbered) environment or a bare `$$`
// display, leaning on its own numbering engine. So whenever a block contains a
// label we force it into a numbered environment: a starred env drops its star,
// and a bare display becomes `equation` (single line) or `gather` (multi-line).
fn ensure_numbered_env(inner: String) -> String {
  let starred = [
    "equation*", "align*", "alignat*", "flalign*", "gather*", "multline*",
    "eqnarray*",
  ]
  case list.find(starred, fn(e) { string.starts_with(inner, "\\begin{" <> e <> "}") }) {
    Ok(star_name) -> {
      let base = string.drop_end(star_name, 1)
      inner
      |> string.replace("\\begin{" <> star_name <> "}", "\\begin{" <> base <> "}")
      |> string.replace("\\end{" <> star_name <> "}", "\\end{" <> base <> "}")
    }
    Error(_) -> inner
  }
}

fn mathblock_to_latex(vxml: VXML, ctx: Ctx) -> String {
  let inner =
    vxml
    |> gather_text
    |> strip_display_delims
    |> transform_math(ctx)
  let has_label = string.contains(inner, "\\label{")
  case is_standalone_env(inner), has_label {
    True, True -> "\n" <> ensure_numbered_env(inner) <> "\n"
    True, False -> "\n" <> inner <> "\n"
    False, True ->
      case string.contains(inner, "\\\\") {
        True -> "\n\\begin{gather}\n" <> inner <> "\n\\end{gather}\n"
        False -> "\n\\begin{equation}\n" <> inner <> "\n\\end{equation}\n"
      }
    False, False -> "\n\\[\n" <> inner <> "\n\\]\n"
  }
}

fn enumerate_opts(attrs: List(Attr)) -> String {
  case find_attr(attrs, "data-list-style") {
    Some("decimal") -> "[label=\\arabic*.]"
    Some("alpha") -> "[label=(\\alph*)]"
    Some("roman") -> "[label=(\\roman*)]"
    // default matches the web renderer's `ol.list` lower-roman markers
    _ -> "[label=(\\roman*)]"
  }
}

fn statement_env(tag: String) -> Result(String, Nil) {
  case tag {
    "Definition" -> Ok("defn")
    "Theorem" -> Ok("thm")
    "Lemma" -> Ok("lem")
    "Corollary" -> Ok("cor")
    "Example" -> Ok("example")
    "Exercise" -> Ok("xexercise")
    _ -> Error(Nil)
  }
}

// ---------------------------------------------------------------------------
// Tree walk
// ---------------------------------------------------------------------------

fn nodes_to_latex(nodes: List(VXML), ctx: Ctx) -> String {
  nodes |> list.map(node_to_latex(_, ctx)) |> string.concat
}

fn label_of(attrs: List(Attr)) -> String {
  case find_attr(attrs, "handle") {
    Some(h) -> "\\label{" <> h <> "}\n"
    None -> ""
  }
}

fn heading(
  level: String,
  attrs: List(Attr),
  children: List(VXML),
  ctx: Ctx,
) -> String {
  let title = find_attr(attrs, "title") |> option.unwrap("")
  "\n\n\\" <> level <> "{" <> emit_mixed(title) <> "}\n"
  <> label_of(attrs)
  <> nodes_to_latex(children, ctx)
  <> "\n"
}

fn node_to_latex(vxml: VXML, ctx: Ctx) -> String {
  case vxml {
    T(_, lines) -> {
      let text = lines |> list.map(fn(l) { l.content }) |> string.join("\n")
      transform_prose(text, ctx)
    }
    V(_, tag, attrs, children) ->
      case tag {
        "Document" -> nodes_to_latex(children, ctx)
        "Chapter" -> heading("chapter", attrs, children, ctx)
        "Section" -> heading("section", attrs, children, ctx)
        "SubSection" -> heading("subsection", attrs, children, ctx)
        "Exercises" ->
          "\n\n\\chapter*{Exercises}\n"
          <> "\\addcontentsline{toc}{chapter}{Exercises}\n"
          <> label_of(attrs)
          <> nodes_to_latex(children, ctx)
          <> "\n"
        "Proof" -> {
          let opt = case find_attr(attrs, "alt-title") {
            Some(t) ->
              "[" <> transform_prose(strip_trailing_period(t), ctx) <> "]"
            None -> ""
          }
          "\n\n\\begin{proof}"
          <> opt
          <> "\n"
          <> nodes_to_latex(children, ctx)
          <> "\n\\end{proof}\n"
        }
        "MathBlock" -> mathblock_to_latex(vxml, ctx)
        "Math" -> gather_text(vxml)
        "i" -> "\\emph{" <> nodes_to_latex(children, ctx) <> "}"
        "b" -> "\\textbf{" <> nodes_to_latex(children, ctx) <> "}"
        "a" -> {
          let href = find_attr(attrs, "href") |> option.unwrap("")
          "\\href{" <> href <> "}{" <> nodes_to_latex(children, ctx) <> "}"
        }
        "ol" ->
          "\n\\begin{enumerate}"
          <> enumerate_opts(attrs)
          <> "\n"
          <> nodes_to_latex(children, ctx)
          <> "\\end{enumerate}\n"
        "ul" ->
          "\n\\begin{itemize}\n"
          <> nodes_to_latex(children, ctx)
          <> "\\end{itemize}\n"
        "li" -> "\\item " <> string.trim(nodes_to_latex(children, ctx)) <> "\n"
        "WriterlyBlankLine" -> "\n\n"
        // dropped: `hr` only separates web footnotes; `Footnote` bodies are
        // inlined at their call sites via \footnote{}.
        "hr" -> ""
        "Footnote" -> ""
        _ ->
          case statement_env(tag) {
            Ok(env) -> {
              let opt = case find_attr(attrs, "label") {
                Some(l) -> "[" <> emit_mixed(l) <> "]"
                None -> ""
              }
              "\n\n\\begin{"
              <> env
              <> "}"
              <> opt
              <> "\n"
              <> label_of(attrs)
              <> nodes_to_latex(children, ctx)
              <> "\n\\end{"
              <> env
              <> "}\n"
            }
            // unknown tag: pass through its children rather than dropping them
            Error(_) -> nodes_to_latex(children, ctx)
          }
      }
  }
}

// ---------------------------------------------------------------------------
// Footnotes: gather `Footnote` bodies keyed by handle, inline at call sites.
// ---------------------------------------------------------------------------

fn find_footnotes(vxml: VXML) -> List(VXML) {
  case vxml {
    T(_, _) -> []
    V(_, "Footnote", _, _) -> [vxml]
    V(_, _, _, children) -> list.flat_map(children, find_footnotes)
  }
}

fn gather_footnotes(root: VXML, ctx: Ctx) -> Dict(String, String) {
  find_footnotes(root)
  |> list.fold(dict.new(), fn(acc, fnode) {
    case fnode {
      V(_, _, attrs, children) ->
        case find_attr(attrs, "handle") {
          Some(name) ->
            dict.insert(acc, name, string.trim(nodes_to_latex(children, ctx)))
          None -> acc
        }
      T(_, _) -> acc
    }
  })
}

// ---------------------------------------------------------------------------
// Preamble + whole-document assembly
// ---------------------------------------------------------------------------

fn preamble(di: DocumentInfo) -> String {
  "\\documentclass[11pt]{report}\n"
  <> "\\usepackage[utf8]{inputenc}\n"
  <> "\\usepackage[T1]{fontenc}\n"
  <> "\\usepackage{amsmath}\n"
  <> "\\usepackage{amssymb}\n"
  <> "\\usepackage{amsthm}\n"
  <> "\\usepackage{enumitem}\n"
  <> "\\usepackage[margin=1in]{geometry}\n"
  <> "\\usepackage{hyperref}\n"
  <> "\\usepackage{bookmark}\n"
  // makes the footnote number at the bottom of the page a hyperlink back to
  // its call site in the running text (requires hyperref; load after it)
  <> "\\usepackage{footnotebackref}\n"
  <> "\\hypersetup{\n"
  <> "  colorlinks=true,\n"
  <> "  linkcolor=blue,\n"
  <> "  citecolor=blue,\n"
  <> "  urlcolor=blue,\n"
  <> "  bookmarksnumbered=true,\n"
  <> "  bookmarksopen=true,\n"
  <> "  pdftitle={" <> escape_prose(di.title) <> "},\n"
  <> "  pdfauthor={" <> escape_prose(di.lecturer) <> "}\n"
  <> "}\n\n"
  <> "\\setcounter{tocdepth}{2}\n\n"
  // stretch the footnote separator rule across the full text width
  <> "\\renewcommand{\\footnoterule}{\\kern-3pt\\hrule width \\textwidth height 0.4pt\\kern2.6pt}\n\n"
  <> "% custom macros carried over from the original lecture-notes preamble\n"
  <> "\\providecommand{\\cal}{\\mathcal}\n"
  <> "\\newcommand{\\R}{\\mathbb{R}}\n"
  <> "\\newcommand{\\Z}{\\mathbb{Z}}\n"
  <> "\\newcommand{\\N}{\\mathbb{N}}\n"
  <> "\\newcommand{\\Q}{\\mathbb{Q}}\n"
  <> "\\newcommand{\\E}{\\mathbb{E}}\n"
  <> "\\newcommand{\\prob}{\\mathbf{P}}\n"
  <> "\\newcommand{\\expec}{\\mathbf{E}}\n"
  <> "\\newcommand{\\var}{\\mathbf{V}}\n"
  <> "\\newcommand{\\cov}{\\textrm{Cov}}\n"
  <> "\\newcommand{\\ind}{\\mathbf{1}}\n"
  <> "\\newcommand{\\eqdist}{\\stackrel{d}{=}}\n\n"
  <> "\\theoremstyle{plain}\n"
  <> "\\newtheorem{thm}{Theorem}[chapter]\n"
  <> "\\newtheorem{lem}[thm]{Lemma}\n"
  <> "\\newtheorem{cor}[thm]{Corollary}\n"
  <> "\\theoremstyle{definition}\n"
  <> "\\newtheorem{defn}[thm]{Definition}\n"
  <> "\\newtheorem{example}[thm]{Example}\n"
  <> "\\newtheorem{xexercise}[thm]{Exercise}\n\n"
  <> "\\title{"
  <> emit_mixed(di.title)
  <> " \\\\ "
  <> emit_mixed(di.course)
  <> " --- "
  <> emit_mixed(di.term)
  <> "}\n"
  <> "\\author{"
  <> emit_mixed(di.lecturer)
  <> " \\\\ "
  <> emit_mixed(di.department)
  <> ", "
  <> emit_mixed(di.institution)
  <> "}\n"
  <> "\\date{" <> emit_mixed(di.date) <> "}\n"
}

fn emit_document(root: VXML, di: DocumentInfo) -> String {
  let assert Ok(tok) = regexp.from_string(token_pattern)
  let assert Ok(math_tok) = regexp.from_string(math_token_pattern)
  let base_ctx = Ctx(dict.new(), tok, math_tok)
  let footnotes = gather_footnotes(root, base_ctx)
  let ctx = Ctx(footnotes, tok, math_tok)
  let body = node_to_latex(root, ctx)
  preamble(di)
  <> "\n\\begin{document}\n\\maketitle\n\\tableofcontents\n\n"
  <> body
  <> "\n\\end{document}\n"
}

// ---------------------------------------------------------------------------
// Renderer plumbing (splitter / emitter / render entry point)
// ---------------------------------------------------------------------------

pub type LatexFragmentType {
  WholeDocument
}

type Fragment(z) =
  ds.OutputFragment(LatexFragmentType, z)

type OL =
  List(OutputLine)

pub type LatexSplitterError {
  EmptyDocument
}

fn our_splitter(
  filename: String,
  root: VXML,
) -> Result(List(Fragment(VXML)), LatexSplitterError) {
  Ok([ds.OutputFragment(WholeDocument, filename, root)])
}

fn our_emitter(
  di: DocumentInfo,
  fragment: Fragment(VXML),
) -> Result(Fragment(OL), String) {
  let blame = Ext([], "latex_emitter")
  let lines =
    emit_document(fragment.payload, di)
    |> string.split("\n")
    |> list.map(fn(line) { OutputLine(blame, 0, line) })
  Ok(ds.OutputFragment(..fragment, payload: lines))
}

pub fn render(amendments: ds.CommandLineAmendments, course_dir: String) -> Nil {
  let #(output_dir_local_path, amendments) = case amendments.output_dir {
    None -> #("latex", amendments)
    Some(x) -> #(x, ds.CommandLineAmendments(..amendments, output_dir: None))
  }
  let assert None = amendments.input_dir
  let assert None = amendments.output_dir

  let parent = course_dir <> "/wly/__parent.wly"
  case simplifile.read(parent) {
    Error(_) -> io.println("\nunable to read '" <> parent <> "'")
    Ok(contents) -> {
      let assembled = io_lines.string_to_input_lines(contents, parent, 0)
      let assert Ok(parsed) = writerly.input_lines_to_vxml(assembled)
      let attr = fn(k: String, default: String) -> String {
        case infra.v_first_attr_with_key(parsed, k) {
          Some(a) -> a.val
          None -> default
        }
      }
      let document_info =
        DocumentInfo(
          title: attr("title", course_dir),
          course: attr("course", ""),
          term: attr("term", ""),
          department: attr("department", ""),
          institution: attr("institution", ""),
          lecturer: attr("lecturer", ""),
          date: attr("date", ""),
        )
      let filename = course_dir <> ".tex"
      let output_dir =
        "./" <> course_dir <> "/" <> output_dir_local_path <> "/"

      let parameters =
        ds.RendererParameters(
          input_dir: "./" <> course_dir <> "/wly/",
          output_dir: output_dir,
          prettifier_behavior: ds.PrettifierOff,
        )
        |> ds.amend_renderer_parameters_by_command_line_amendments(amendments)

      let options =
        ds.vanilla_options()
        |> ds.amend_renderer_options_by_command_line_amendments(amendments)

      let renderer =
        ds.Renderer(
          assembler: wd.default_writerly_assembler(_, options),
          parser: wd.default_writerly_parser,
          filterer: ds.default_filterer(_, options, []),
          pipeline: latex_pipeline.latex_pipeline(),
          splitter: our_splitter(filename, _),
          emitter: our_emitter(document_info, _),
          writer: ds.default_writer,
          prettifier: ds.default_prettier_prettifier,
        )
        |> ds.amend_renderer_by_command_line_amendments(amendments)

      case ds.run_renderer(renderer, parameters, options) {
        Error(error) ->
          io.println("\nlatex renderer error: " <> ins(error) <> "\n")
        _ -> io.println("\nwrote " <> output_dir <> filename <> "\n")
      }
    }
  }
}
