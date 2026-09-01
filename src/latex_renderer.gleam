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
import vxml.{type Attr, type VXML, Attr, Line, T, V}
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
//   (>>eq:name) parenthesized equation reference -> \eqref{eq:name} (the parens
//               are dropped; \eqref supplies its own "(N)")
//   >>name      cross-reference           -> \ref{name}
//   name##<<    equation/label definition -> \label{name}
// The name charset is exactly what Writerly handles use (letters, digits, `_`,
// `:`, `-`). It deliberately excludes `.` so a ref at a sentence end, `>>thm-x.`,
// does not swallow the trailing period into the label name. The `(>>eq:…)`
// alternative must precede the bare `>>…` so the surrounding parens are consumed.
const token_pattern = "\\(\\*>>[A-Za-z][A-Za-z0-9_:-]*\\)|\\(>>eq:[A-Za-z0-9_:-]*\\)|>>[A-Za-z][A-Za-z0-9_:-]*|[A-Za-z][A-Za-z0-9_:-]*##<<"

// Inside math we only rewrite refs and labels (never footnotes, never escape).
const math_token_pattern = ">>[A-Za-z][A-Za-z0-9_:-]*|[A-Za-z][A-Za-z0-9_:-]*##<<"

// Emit context threaded through the tree walk.
type Ctx {
  Ctx(
    footnotes: Dict(String, String),
    // handle -> global equation number (matches the HTML `::++EquationCounter`)
    eq_numbers: Dict(String, Int),
    tok: Regexp,
    math_tok: Regexp,
    // matches an eqnarray relation column `&...&`, for the eqnarray->align fixup
    amp_tok: Regexp,
  )
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

// Escape the characters that break inside `\href{...}`'s URL argument. `#` is
// the critical one: a raw `#` in an href URL inside a `\footnote` (a moving
// argument) triggers "Illegal parameter number"; `\#` is safe everywhere.
fn escape_url(s: String) -> String {
  s
  |> string.replace("#", "\\#")
  |> string.replace("%", "\\%")
}

fn strip_trailing_period(s: String) -> String {
  case string.ends_with(s, ".") {
    True -> string.drop_end(s, 1)
    False -> s
  }
}

// The single hyperlink whose visible text is "<Name> <number>":
// `\hyperref[handle]{Name~\ref*{handle}}`. The `~` keeps name and number on one
// line; `\ref*` gives the number without nesting a second link. Reusing the
// author's own word as the link text sidesteps `\autoref` (which would print
// "Theorem" for every shared-counter theorem-like environment, incl.
// lemmas/definitions).
fn named_ref_hyperref(name: String, handle: String) -> String {
  "\\hyperref[" <> handle <> "]{" <> name <> "~\\ref*{" <> handle <> "}}"
}

// Split a raw "<Name>  >>handle" match into #(name, handle). The whitespace
// between the two is `\s+` (it may be a source line break, so a newline), hence
// we split on `>>` and trim the name rather than on a literal " >>".
fn split_named_ref(raw: String) -> Result(#(String, String), Nil) {
  case string.split_once(raw, ">>") {
    Ok(#(name_ws, handle)) -> Ok(#(string.trim(name_ws), handle))
    Error(_) -> Error(Nil)
  }
}

// Body-prose form (normal, non-moving context): the plain hyperlink.
fn named_ref_to_latex(raw: String) -> String {
  case split_named_ref(raw) {
    Ok(#(name, handle)) -> named_ref_hyperref(name, handle)
    // only ever fed a well-formed "<Name> >>handle"; if that changes, degrade
    // gracefully to plain prose instead of emitting broken LaTeX.
    Error(_) -> escape_prose(raw)
  }
}

// Moving-argument-safe form for named refs that land inside a fragile optional
// argument — notably a Proof's `alt-title=Proof of Theorem >>h`, which becomes
// amsthm's proof `[...]` header. A bare `\hyperref` is fatal there
// (`\Hy@babelnormalise has an extra }`); `\texorpdfstring{<hyperref>}{<Name>}`
// typesets the hyperlink but hands hyperref a plain-text version for its
// PDF-string pass, which is what makes it survive.
fn named_ref_to_latex_robust(raw: String) -> String {
  case split_named_ref(raw) {
    Ok(#(name, handle)) ->
      "\\texorpdfstring{"
      <> named_ref_hyperref(name, handle)
      <> "}{"
      <> name
      <> "}"
    Error(_) -> escape_prose(raw)
  }
}

// The `AutoRef` node the pipeline builds from body-prose named refs carries the
// literal "<Name> >>handle" in its `ref` attribute.
fn autoref_to_latex(attrs: List(Attr)) -> String {
  named_ref_to_latex(find_attr(attrs, "ref") |> option.unwrap(""))
}

// Regex alternative matching a "<Name> >>handle" named ref, built from the SAME
// word list the pipeline splitter uses. Prepended to `token_pattern` so the
// emitter also recognizes named refs that live in attributes (e.g. a Proof's
// `alt-title`), which never become text nodes and so are out of the pipeline
// splitter's reach.
fn named_ref_pattern() -> String {
  "\\b(?:"
  <> string.join(latex_pipeline.autoref_words, "|")
  <> ")\\s+>>[A-Za-z][A-Za-z0-9_:-]*"
}

// Normalize a path for created/deleted set comparison: `simplifile.get_files`
// and our `output_dir <> path` concatenation can differ only by a leading
// `./`, so drop it from both sides.
fn drop_dot_slash(s: String) -> String {
  case string.starts_with(s, "./") {
    True -> string.drop_start(s, 2)
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
  // A named ref "<Name> >>handle" is the only token with a WORD before the `>>`
  // (the whitespace may be a source line break, so we can't test for a literal
  // " >>"). It therefore starts with a letter — NOT `>>` (bare ref) and NOT `(`
  // (footnote `(*>>…)` or parenthesized eq ref `(>>eq:…)`). It can land in a
  // fragile moving argument (Proof `alt-title`), so use the robust
  // `\texorpdfstring` form.
  let is_named_ref =
    string.contains(token, ">>")
    && !string.starts_with(token, ">>")
    && !string.starts_with(token, "(")
  case is_named_ref {
    True -> named_ref_to_latex_robust(token)
    False -> prose_ref_token_to_latex(token, ctx)
  }
}

fn prose_ref_token_to_latex(token: String, ctx: Ctx) -> String {
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
      // parenthesized equation ref `(>>eq:name)` -> `\eqref{eq:name}` (drop the
      // author's parens; `\eqref` prints its own "(N)")
      case string.starts_with(token, "(>>") {
        True ->
          "\\eqref{"
          <> token |> string.drop_start(3) |> string.drop_end(1)
          <> "}"
        False ->
          case string.starts_with(token, ">>") {
            True -> "\\ref{" <> string.drop_start(token, 2) <> "}"
            False -> "\\label{" <> string.drop_end(token, 4) <> "}"
          }
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
          before
          <> math_token_to_latex(m.content, ctx)
          <> transform_math(after, ctx)
        Error(_) -> s
      }
  }
}

fn math_token_to_latex(token: String, ctx: Ctx) -> String {
  case string.starts_with(token, ">>") {
    True -> "\\ref{" <> string.drop_start(token, 2) <> "}"
    False -> {
      // `name##<<`: give this equation its global sequence number as an
      // explicit `\tag{N}` (identical to the HTML renderer's
      // ::++EquationCounter), then `\label` it so `\ref` resolves to that N.
      let name = string.drop_end(token, 4)
      let tag = case dict.get(ctx.eq_numbers, name) {
        Ok(n) -> "\\tag{" <> int.to_string(n) <> "}"
        Error(_) -> ""
      }
      tag <> "\\label{" <> name <> "}"
    }
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

// Match the HTML renderer's numbering exactly: an equation is numbered ONLY when
// it carries an explicit tag -- either a manual mnemonic tag already in the
// source (`\tag{A1}`, ...) or the global sequence number baked at a `name##<<`
// marker (`\tag{N}`, above). Nothing else is numbered. So we emit every
// standalone environment in its STARRED, non-auto-numbering form and let the
// `\tag`s alone drive the visible numbers (`\tag` works in starred environments).
fn starify_env(inner: String) -> String {
  let unstarred = [
    "equation", "align", "alignat", "flalign", "gather", "multline", "eqnarray",
  ]
  case
    list.find(unstarred, fn(e) {
      string.starts_with(inner, "\\begin{" <> e <> "}")
    })
  {
    Ok(name) ->
      inner
      |> string.replace("\\begin{" <> name <> "}", "\\begin{" <> name <> "*}")
      |> string.replace("\\end{" <> name <> "}", "\\end{" <> name <> "*}")
    Error(_) -> inner
  }
}

// `eqnarray`/`eqnarray*` is legacy LaTeX and does NOT accept amsmath's `\tag`.
// When such a block needs a tag, convert it to `align*` (which does): rename the
// environment and collapse eqnarray's 3-column `& REL &` alignment down to
// align's 2-column `& REL`. This is only applied to tagged blocks, which in this
// corpus never nest a `&`-using environment (cases/array/matrix), so the flat
// column collapse is safe.
fn collapse_eqnarray_cols(s: String, amp_re: Regexp) -> String {
  case regexp.scan(amp_re, s) {
    [] -> s
    [m, ..] ->
      case string.split_once(s, m.content) {
        Ok(#(before, after)) ->
          before
          <> string.drop_end(m.content, 1)
          <> collapse_eqnarray_cols(after, amp_re)
        Error(_) -> s
      }
  }
}

fn eqnarray_to_align(inner: String, amp_re: Regexp) -> String {
  inner
  |> string.replace("\\begin{eqnarray*}", "\\begin{align*}")
  |> string.replace("\\begin{eqnarray}", "\\begin{align*}")
  |> string.replace("\\end{eqnarray*}", "\\end{align*}")
  |> string.replace("\\end{eqnarray}", "\\end{align*}")
  |> collapse_eqnarray_cols(amp_re)
}

fn mathblock_to_latex(vxml: VXML, ctx: Ctx) -> String {
  let inner =
    vxml
    |> gather_text
    |> strip_display_delims
    |> transform_math(ctx)
  let has_tag = string.contains(inner, "\\tag{")
  let is_eqnarray =
    string.starts_with(inner, "\\begin{eqnarray}")
    || string.starts_with(inner, "\\begin{eqnarray*}")
  case is_eqnarray && has_tag, is_standalone_env(inner), has_tag {
    // tagged eqnarray -> align* (eqnarray can't carry \tag)
    True, _, _ -> "\n" <> eqnarray_to_align(inner, ctx.amp_tok) <> "\n"
    // starred env: unnumbered by default, but any `\tag` inside still numbers
    _, True, _ -> "\n" <> starify_env(inner) <> "\n"
    // bare display carrying a tag: needs an env in which `\tag` is legal
    _, False, True ->
      case string.contains(inner, "\\\\") {
        True -> "\n\\begin{gather*}\n" <> inner <> "\n\\end{gather*}\n"
        False -> "\n\\begin{equation*}\n" <> inner <> "\n\\end{equation*}\n"
      }
    // A bare display containing an `array` can be a wide table that overflows
    // the page (e.g. the "Summary of special distributions" grid). Route it
    // through `\fitwidth`, which scales it down only if it exceeds \linewidth.
    _, False, False ->
      case string.contains(inner, "\\begin{array}") {
        True ->
          "\n\\begin{center}\n\\fitwidth{$\\displaystyle\n"
          <> inner
          <> "\n$}\n\\end{center}\n"
        False -> "\n\\[\n" <> inner <> "\n\\]\n"
      }
  }
}

fn enumerate_opts(attrs: List(Attr)) -> String {
  let label = case find_attr(attrs, "data-list-style") {
    Some("decimal") -> "label=\\arabic*."
    Some("alpha") -> "label=(\\alph*)"
    Some("roman") -> "label=(\\roman*)"
    // default matches the web renderer's `ol.list` lower-roman markers
    _ -> "label=(\\roman*)"
  }
  // `start=N` continues numbering across a split list (the bibliography numbers
  // its references 1..10 across three "Sources for Part k" sublists).
  let start = case find_attr(attrs, "start") {
    Some(n) -> ", start=" <> n
    None -> ""
  }
  "[" <> label <> start <> "]"
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
// Figures
//
// Two source shapes are supported:
//   235B: `figure` > (`img`+ , `figcaption`)          -- images directly
//   119B: `figure` > (`span`(width%){ `img` (a) }+ , `figcaption`)
//                                                       -- labelled panels
// Each image/panel becomes a fixed-width box; boxes flow side by side and wrap
// to a grid when a row exceeds \linewidth. The caption goes below. We do NOT use
// `\caption`/`figure` floats: the source hard-numbers figures ("Figure N:") in
// the caption text and refers to them by that literal number in prose, so LaTeX
// auto-numbering would clash.
// ---------------------------------------------------------------------------

// Width fraction (e.g. "0.44") from a CSS-ish `style` holding `width: N%` or
// `max-width: N%` (the `width:` substring of `max-width:` matches too).
fn style_width_fraction(style: Option(String), default: String) -> String {
  let assert Ok(re) = regexp.from_string("width:\\s*([0-9]+)")
  case style {
    Some(s) ->
      case regexp.scan(re, s) {
        [m, ..] ->
          case m.submatches {
            [Some("100")] -> "1.0"
            // source percentages are otherwise two digits, e.g. "38" -> "0.38"
            [Some(pct)] -> "0." <> pct
            _ -> default
          }
        [] -> default
      }
    None -> default
  }
}

// `\includegraphics` for a direct `img` (235B-style), width from `max-width: N%`.
fn img_to_latex(attrs: List(Attr)) -> String {
  let src = find_attr(attrs, "src") |> option.unwrap("")
  let frac = style_width_fraction(find_attr(attrs, "style"), "0.8")
  "\\includegraphics[width=" <> frac <> "\\linewidth]{" <> src <> "}"
}

// A `span` panel (119B-style): a fixed-width box wrapping an image (shown at the
// box's full width) and an optional label like "(a)", as a top-aligned minipage.
fn span_panel_to_latex(
  attrs: List(Attr),
  children: List(VXML),
  ctx: Ctx,
) -> String {
  let frac = style_width_fraction(find_attr(attrs, "style"), "0.44")
  let parts =
    children
    |> list.filter_map(fn(c) {
      case c {
        V(_, "img", ia, _) ->
          Ok(
            "\\includegraphics[width=\\linewidth]{"
            <> { find_attr(ia, "src") |> option.unwrap("") }
            <> "}",
          )
        V(_, "WriterlyBlankLine", _, _) -> Error(Nil)
        _ ->
          case string.trim(node_to_latex(c, ctx)) {
            "" -> Error(Nil)
            t -> Ok(t)
          }
      }
    })
  "\\begin{minipage}[t]{"
  <> frac
  <> "\\linewidth}\\centering\n"
  <> string.join(parts, "\\\\\n")
  <> "\n\\end{minipage}"
}

fn figure_to_latex(children: List(VXML), ctx: Ctx) -> String {
  let panels =
    children
    |> list.filter_map(fn(c) {
      case c {
        V(_, "img", attrs, _) -> Ok(img_to_latex(attrs))
        V(_, "span", attrs, sc) -> Ok(span_panel_to_latex(attrs, sc, ctx))
        _ -> Error(Nil)
      }
    })
    // breakable gap: a row of panels wider than \linewidth wraps to a grid
    |> string.join("\\hspace{0.02\\linewidth}%\n")
  let caption =
    children
    |> list.find_map(fn(c) {
      case c {
        V(_, "figcaption", _, cc) -> Ok(nodes_to_latex(cc, ctx))
        _ -> Error(Nil)
      }
    })
  let caption_latex = case caption {
    Ok(text) -> "\\\\[0.6em]\n{\\small " <> string.trim(text) <> "}"
    Error(_) -> ""
  }
  "\n\\begin{center}\n" <> panels <> caption_latex <> "\n\\end{center}\n"
}

// ---------------------------------------------------------------------------
// Tree walk
// ---------------------------------------------------------------------------

// Paragraph-indentation state carried while walking a sibling list.
//
// LaTeX indents the first line of every paragraph by default; authors want that
// only BETWEEN consecutive text paragraphs. A paragraph that follows a display,
// an environment, a list, etc. is a continuation and should NOT be indented, so
// we emit `\noindent` before it. A bare `|> Indent` marker overrides that and
// forces `\indent` on the next paragraph. (Paragraphs after a heading are left
// to the class default, which already suppresses their indent.)
type IndentHint {
  HintDefault
  HintNoindent
  HintIndent
}

type NodeKind {
  KInline
  KBlank
  KBlock
  KIndent
}

fn node_kind(node: VXML) -> NodeKind {
  case node {
    T(_, _) -> KInline
    V(_, "Math", _, _)
    | V(_, "i", _, _)
    | V(_, "b", _, _)
    | V(_, "a", _, _)
    | V(_, "AutoRef", _, _) -> KInline
    V(_, "WriterlyBlankLine", _, _) -> KBlank
    V(_, "Indent", _, _) -> KIndent
    V(_, _, _, _) -> KBlock
  }
}

// Emit one node while threading the paragraph state. Returns the updated
// `#(in_paragraph, hint)` and the node's output.
// A text node whose content is empty/whitespace (a common leftover of the
// delimiter splitting). It must not start a paragraph or swallow the pending
// indent hint, so it is skipped entirely.
fn is_blank_text(node: VXML) -> Bool {
  case node {
    T(_, lines) ->
      lines |> list.map(fn(l) { l.content }) |> string.concat |> string.trim
      == ""
    _ -> False
  }
}

fn emit_indented(
  node: VXML,
  in_para: Bool,
  hint: IndentHint,
  ctx: Ctx,
) -> #(Bool, IndentHint, String) {
  case is_blank_text(node) {
    True -> #(in_para, hint, "")
    False -> emit_indented_node(node, in_para, hint, ctx)
  }
}

fn emit_indented_node(
  node: VXML,
  in_para: Bool,
  hint: IndentHint,
  ctx: Ctx,
) -> #(Bool, IndentHint, String) {
  case node_kind(node) {
    KInline -> {
      let prefix = case in_para, hint {
        True, _ -> ""
        False, HintNoindent -> "\\noindent "
        False, HintIndent -> "\\indent "
        False, HintDefault -> ""
      }
      #(True, HintDefault, prefix <> node_to_latex(node, ctx))
    }
    // a blank line ends the current paragraph; the next paragraph defaults to
    // indented iff we were mid-text, else it keeps the preceding block/marker's
    // hint
    KBlank -> {
      let next_hint = case in_para {
        True -> HintDefault
        False -> hint
      }
      #(False, next_hint, "\n\n")
    }
    KBlock -> #(False, HintNoindent, node_to_latex(node, ctx))
    KIndent -> #(False, HintIndent, "")
  }
}

fn nodes_to_latex(nodes: List(VXML), ctx: Ctx) -> String {
  let #(_, _, out) =
    list.fold(nodes, #(False, HintDefault, ""), fn(acc, node) {
      let #(in_para, hint, out) = acc
      let #(in_para, hint, chunk) = emit_indented(node, in_para, hint, ctx)
      #(in_para, hint, out <> chunk)
    })
  out
}

fn label_of(attrs: List(Attr)) -> String {
  case find_attr(attrs, "handle") {
    Some(h) -> "\\label{" <> h <> "}\n"
    None -> ""
  }
}

// The `\chapter{…}` / `\section{…}` / `\subsection{…}` line plus a `\label`,
// with no body — shared by the inline emitter (`heading`) and the modular
// file-splitting walk.
fn heading_open(level: String, attrs: List(Attr)) -> String {
  let title = find_attr(attrs, "title") |> option.unwrap("")
  // trailing blank line: keep `\<level>{…}` (and its `\label`) visually separated
  // from the body that follows.
  "\n\n\\"
  <> level
  <> "{"
  <> emit_mixed(title)
  <> "}\n"
  <> label_of(attrs)
  <> "\n"
}

// The `\chapter*{…}` head (+ `\addcontentsline` + `\label`) for a standalone
// appendix unit (Exercises / Bibliography), no body.
fn standalone_open(tag: String, attrs: List(Attr)) -> String {
  let t = find_attr(attrs, "title") |> option.unwrap(tag) |> emit_mixed
  "\n\n\\chapter*{"
  <> t
  <> "}\n\\addcontentsline{toc}{chapter}{"
  <> t
  <> "}\n"
  <> label_of(attrs)
}

fn heading(
  level: String,
  attrs: List(Attr),
  children: List(VXML),
  ctx: Ctx,
) -> String {
  heading_open(level, attrs) <> nodes_to_latex(children, ctx) <> "\n"
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
        // standalone appendix units (outside the numbered chapter sequence):
        // an unnumbered \chapter* that still appears in the TOC + outline.
        "Exercises" | "Bibliography" ->
          standalone_open(tag, attrs) <> nodes_to_latex(children, ctx) <> "\n"
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
        "figure" -> figure_to_latex(children, ctx)
        // `img`/`figcaption` outside a `figure` are a fallback (normally the
        // `figure` case consumes them); render sensibly anyway.
        "img" ->
          "\n\\begin{center}\n" <> img_to_latex(attrs) <> "\n\\end{center}\n"
        "figcaption" -> "{\\small " <> nodes_to_latex(children, ctx) <> "}"
        // a `span` outside a figure is just an inline grouping; emit its content
        "span" -> nodes_to_latex(children, ctx)
        "MathBlock" -> mathblock_to_latex(vxml, ctx)
        "Math" -> gather_text(vxml)
        "i" -> "\\emph{" <> nodes_to_latex(children, ctx) <> "}"
        "b" -> "\\textbf{" <> nodes_to_latex(children, ctx) <> "}"
        "a" -> {
          let href = find_attr(attrs, "href") |> option.unwrap("")
          "\\href{"
          <> escape_url(href)
          <> "}{"
          <> nodes_to_latex(children, ctx)
          <> "}"
        }
        // A named cross-reference ("Theorem >>handle", "Lemma >>handle", …),
        // recognized in the pipeline (`autoref_named_links_splitter`) and carried
        // here as `ref="<Name> >>handle"`. Render the WHOLE "Name 3.14" as one
        // hyperlink by reusing the author's own word as the link text:
        // `\hyperref[handle]{Name~\ref*{handle}}` (the `~` keeps name+number on
        // one line; `\ref*` yields the number without nesting a second link).
        // We deliberately do NOT use `\autoref`: all theorem-like environments
        // share the `thm` counter, so `\autoref` would label every one of them
        // "Theorem" regardless of kind.
        "AutoRef" -> autoref_to_latex(attrs)
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
        // paragraph-indent marker: consumed by `emit_indented`, no direct output
        "Indent" -> ""
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
  // Latin Modern: full Type-1 VECTOR fonts for the T1 encoding. Without it,
  // T1 + Computer Modern falls back to Type-3 BITMAP fonts (blurry at any zoom)
  // on TeX installs lacking cm-super.
  <> "\\usepackage{lmodern}\n"
  <> "\\usepackage[T1]{fontenc}\n"
  <> "\\usepackage{amsmath}\n"
  <> "\\usepackage{amssymb}\n"
  <> "\\usepackage{amsthm}\n"
  <> "\\usepackage{enumitem}\n"
  <> "\\usepackage[margin=1in]{geometry}\n"
  <> "\\usepackage{graphicx}\n"
  // microtype (char protrusion + font expansion) removes most marginal overflow
  <> "\\usepackage{microtype}\n"
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
  <> "  pdftitle={"
  <> escape_prose(di.title)
  <> "},\n"
  <> "  pdfauthor={"
  <> escape_prose(di.lecturer)
  <> "}\n"
  <> "}\n\n"
  <> "\\setcounter{tocdepth}{2}\n"
  // let TeX loosen a line as a last resort instead of running text off the page
  // (mainly the source's long unbreakable `$\\textbf{...}$` prose phrases)
  <> "\\emergencystretch=3em\n\n"
  // stretch the footnote separator rule across the full text width
  <> "\\renewcommand{\\footnoterule}{\\kern-3pt\\hrule width \\textwidth height 0.4pt\\kern2.6pt}\n\n"
  // shrink an over-wide box down to the text width, but leave narrower content
  // untouched (used for wide display tables that would otherwise overflow)
  <> "\\newsavebox{\\fitbox}\n"
  <> "\\newcommand{\\fitwidth}[1]{%\n"
  <> "  \\sbox\\fitbox{#1}%\n"
  <> "  \\ifdim\\wd\\fitbox>\\linewidth\\resizebox{\\linewidth}{!}{\\usebox\\fitbox}\\else\\usebox\\fitbox\\fi}\n\n"
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
  <> "\\date{"
  <> emit_mixed(di.date)
  <> "}\n"
}

// Assign each `name##<<` marker its global equation number by document order
// (the k-th marker overall becomes equation k), mirroring how the HTML
// renderer's ::++EquationCounter increments. The tree is walked in the same
// left-to-right, depth-first order the emitter uses.
fn collect_eq_labels(vxml: VXML, math_tok: Regexp) -> List(String) {
  case vxml {
    T(_, lines) -> {
      let text = lines |> list.map(fn(l) { l.content }) |> string.join("\n")
      regexp.scan(math_tok, text)
      |> list.filter(fn(m) { string.ends_with(m.content, "##<<") })
      |> list.map(fn(m) { string.drop_end(m.content, 4) })
    }
    V(_, _, _, children) ->
      list.flat_map(children, collect_eq_labels(_, math_tok))
  }
}

// Footnotes and equation numbers are GLOBAL, so the context is built once from
// the whole tree and shared by every emitted file (monolithic or modular).
fn build_ctx(root: VXML) -> Ctx {
  // named-ref alternative FIRST so "Theorem >>h" is matched as a whole (and
  // hyperlinked name+number) rather than just its trailing `>>h`. In body prose
  // the pipeline already turned these into `AutoRef` nodes, so this only fires
  // for named refs stuck in attributes (Proof `alt-title`).
  let assert Ok(tok) =
    regexp.from_string(named_ref_pattern() <> "|" <> token_pattern)
  let assert Ok(math_tok) = regexp.from_string(math_token_pattern)
  let assert Ok(amp_tok) = regexp.from_string("&[^&]*&")
  let eq_numbers =
    collect_eq_labels(root, math_tok)
    |> list.index_map(fn(name, i) { #(name, i + 1) })
    |> dict.from_list
  let base_ctx = Ctx(dict.new(), eq_numbers, tok, math_tok, amp_tok)
  let footnotes = gather_footnotes(root, base_ctx)
  Ctx(footnotes, eq_numbers, tok, math_tok, amp_tok)
}

// Wrap a document body in the preamble, `\begin{document}`, title, contents and
// `\end{document}`. Used for both the single monolithic file and the modular
// `main.tex` (whose body is a list of `\input{…}` lines).
fn wrap_document(di: DocumentInfo, body: String) -> String {
  collapse_blank_lines(
    preamble(di)
    // `\pdfbookmark[0]{Contents}{toc}` adds a top-level, unnumbered PDF outline
    // entry for the table of contents itself (which \tableofcontents does not
    // bookmark on its own), pointing at the TOC page.
    <> "\n\\begin{document}\n\\maketitle\n"
    <> "\\pdfbookmark[0]{Contents}{toc}\n"
    <> "\\tableofcontents\n\n"
    <> body
    <> "\n\\end{document}\n",
  )
}

fn emit_document(root: VXML, di: DocumentInfo) -> String {
  wrap_document(di, node_to_latex(root, build_ctx(root)))
}

// ---------------------------------------------------------------------------
// Modular output
//
// `--latex-monolithic` writes a single self-contained `main.tex`. The three modular flags
// write a `main.tex` (preamble + title + TOC + `\input{…}` lines) plus a
// `chapters/` tree. The layout is HIERARCHICAL, and a unit becomes a FOLDER only
// when it actually holds split children (never an empty subfolder):
//
//   --latex-chapters     chapters/01.tex … chapters/16.tex   (chapters are files)
//   --latex-sections     chapters/01/01.tex + chapters/01/sections/01.tex …
//                       (a sectionless chapter stays a file chapters/05.tex)
//   --latex-subsections  … chapters/01/sections/07/07.tex
//                          + chapters/01/sections/07/subsections/1.tex …
//
// A numbered folder `NN/` always contains its own `NN.tex` root file. Names in a
// container start at 1 and are zero-padded (`01`) only when the container holds
// 10+ items, else plain (`1`). Standalone units (Exercises / Bibliography) are
// leaf files `chapters/exercises.tex` / `chapters/bibliography.tex`.
//
// `\input` paths are written relative to `main.tex` (fully qualified), so plain
// `\input` resolves them regardless of which file does the including.
// ---------------------------------------------------------------------------

pub type Granularity {
  Monolithic
  ByChapter
  BySection
  BySubSection
}

fn max_split(g: Granularity) -> Int {
  case g {
    Monolithic -> 0
    ByChapter -> 1
    BySection -> 2
    BySubSection -> 3
  }
}

fn latex_cmd(tag: String) -> String {
  case tag {
    "Chapter" -> "chapter"
    "Section" -> "section"
    _ -> "subsection"
  }
}

fn child_struct_tag(tag: String) -> String {
  case tag {
    "Chapter" -> "Section"
    "Section" -> "SubSection"
    _ -> ""
  }
}

type Files =
  List(#(String, String))

// Numbered names within a container start at 1 and are zero-padded to the width
// of the item count — but only when there are 10+ items (so `1,2,3` for a
// handful, `01,…,16` for many).
fn pad_width(count: Int) -> Int {
  string.length(int.to_string(int.max(count, 1)))
}

fn pad(n: Int, width: Int) -> String {
  let s = int.to_string(n)
  string.repeat("0", int.max(0, width - string.length(s))) <> s
}

fn is_v_tag(node: VXML, tag: String) -> Bool {
  case node {
    V(_, t, _, _) -> tag != "" && t == tag
    _ -> False
  }
}

fn count_tag(children: List(VXML), tag: String) -> Int {
  list.count(children, is_v_tag(_, tag))
}

// The subfolder a chapter/section unit uses to hold its split children.
fn child_container(level: Int) -> String {
  case level {
    1 -> "sections"
    _ -> "subsections"
  }
}

// Emit one split structural unit living in directory `dir`, named `num` (already
// padded). Returns the `\input{…}` line for the parent plus this unit's file(s):
//   - a FOLDER `dir/num/num.tex` + a child container, when the unit's structural
//     children are themselves split and non-empty;
//   - otherwise a plain FILE `dir/num.tex` with everything inline.
// (`\input` paths are relative to the root `main.tex`, hence fully qualified.)
fn hier_unit(
  node: VXML,
  dir: String,
  num: String,
  level: Int,
  ms: Int,
  ctx: Ctx,
) -> #(String, Files) {
  let assert V(_, tag, attrs, children) = node
  let gtag = child_struct_tag(tag)
  let is_folder = level + 1 <= ms && count_tag(children, gtag) > 0
  case is_folder {
    True -> {
      let self = dir <> "/" <> num <> "/" <> num
      let sub = dir <> "/" <> num <> "/" <> child_container(level)
      let #(inner, sub_files) =
        hier_children(children, sub, gtag, level + 1, ms, ctx)
      let content = heading_open(latex_cmd(tag), attrs) <> "\n" <> inner
      #("\n\\input{" <> self <> "}\n", [#(self <> ".tex", content), ..sub_files])
    }
    False -> {
      let self = dir <> "/" <> num
      let content =
        heading_open(latex_cmd(tag), attrs) <> nodes_to_latex(children, ctx)
      #("\n\\input{" <> self <> "}\n", [#(self <> ".tex", content)])
    }
  }
}

// Walk a unit's children into the parent's `.tex` body: each structural child
// (tag == `struct_tag`) becomes an `\input` + its own file(s); everything else
// (intro prose, statements, …) stays inline.
fn hier_children(
  children: List(VXML),
  dir: String,
  struct_tag: String,
  level: Int,
  ms: Int,
  ctx: Ctx,
) -> #(String, Files) {
  let width = pad_width(count_tag(children, struct_tag))
  // thread the paragraph-indent state (see `emit_indented`) across the intro
  // prose; a split-out structural child counts as a block for that purpose.
  let #(_, _, _, text, files) =
    list.fold(children, #(0, False, HintDefault, "", []), fn(acc, child) {
      let #(cnt, in_para, hint, text, files) = acc
      case is_v_tag(child, struct_tag) {
        True -> {
          let cnt = cnt + 1
          let #(inp, cf) =
            hier_unit(child, dir, pad(cnt, width), level, ms, ctx)
          #(cnt, False, HintNoindent, text <> inp, list.append(files, cf))
        }
        False -> {
          let #(in_para, hint, chunk) = emit_indented(child, in_para, hint, ctx)
          #(cnt, in_para, hint, text <> chunk, files)
        }
      }
    })
  #(text, files)
}

// A standalone unit (Exercises / Bibliography) is a leaf file in `chapters/`,
// named by its kind (it has no sub-structure to split).
fn standalone_hier(node: VXML, name: String, ctx: Ctx) -> #(String, Files) {
  let assert V(_, tag, attrs, children) = node
  let content =
    standalone_open(tag, attrs) <> nodes_to_latex(children, ctx) <> "\n"
  let path = "chapters/" <> name
  #("\n\\input{" <> path <> "}\n", [#(path <> ".tex", content)])
}

// Walk the Document's children into the modular main-body + all unit files.
// Chapters and the standalone units live under `chapters/`.
fn hier_document(root: VXML, ms: Int, ctx: Ctx) -> #(String, Files) {
  let assert V(_, _, _, children) = root
  let width = pad_width(count_tag(children, "Chapter"))
  let #(_, body, files) =
    list.fold(children, #(0, "", []), fn(acc, child) {
      let #(cnt, body, files) = acc
      case child {
        V(_, "Chapter", _, _) -> {
          let cnt = cnt + 1
          let #(inp, cf) =
            hier_unit(child, "chapters", pad(cnt, width), 1, ms, ctx)
          #(cnt, body <> inp, list.append(files, cf))
        }
        V(_, "Exercises", _, _) -> {
          let #(inp, cf) = standalone_hier(child, "exercises", ctx)
          #(cnt, body <> inp, list.append(files, cf))
        }
        V(_, "Bibliography", _, _) -> {
          let #(inp, cf) = standalone_hier(child, "bibliography", ctx)
          #(cnt, body <> inp, list.append(files, cf))
        }
        _ -> #(cnt, body <> node_to_latex(child, ctx), files)
      }
    })
  #(body, files)
}

// The full set of #(relative_path, content) files for the chosen granularity.
fn build_latex_files(root: VXML, di: DocumentInfo, gran: Granularity) -> Files {
  let files = case gran {
    // one self-contained file: the root folder holds only `main.tex`
    Monolithic -> [#("main.tex", emit_document(root, di))]
    _ -> {
      let ctx = build_ctx(root)
      let #(main_body, files) = hier_document(root, max_split(gran), ctx)
      [#("main.tex", wrap_document(di, main_body)), ..files]
    }
  }
  files |> list.map(fn(pc) { #(pc.0, tidy_file(pc.1)) })
}

// Final per-file whitespace tidy. The per-node emitters prefix headings/blocks
// with `\n\n`, which — at the very start of a split file — leaves two blank
// lines above the leading `\chapter`/`\section`, and similar padding trails the
// end. Collapse internal 3+ newline runs to one blank line, strip the leading
// and trailing blank lines outright, and end with exactly one newline. Purely
// cosmetic: leading/trailing blank lines around an `\input`ed heading are
// ignored by TeX, so the compiled PDF is unchanged; the `.tex` just reads clean.
fn tidy_file(s: String) -> String {
  collapse_blank_lines(s) |> string.trim <> "\n"
}

// The per-node emitters each pad their output with blank lines, which stack up
// into long runs of empties (a `WriterlyBlankLine` plus a block's own `\n\n`
// prefix, etc.). Collapse any run of 3+ newlines to a single blank line — this
// only ever removes blank lines, and one blank line is still a LaTeX paragraph
// break, so nothing about the compiled output changes; the source just reads
// better.
fn collapse_blank_lines(s: String) -> String {
  let assert Ok(re) = regexp.from_string("\n{3,}")
  regexp.replace(re, s, "\n\n")
}

// ---------------------------------------------------------------------------
// Renderer plumbing (splitter / emitter / render entry point)
// ---------------------------------------------------------------------------

// The classifier is a small routing tag only — every fragment here is just "a
// LaTeX file", so a single nullary variant suffices. The per-file `.tex` content
// (the splitter has the root, document info and granularity to render it all)
// travels in the fragment PAYLOAD, one `Line` per output line, and the emitter
// turns those into `OutputLine`s. (Do NOT stuff the content into the classifier:
// `--verbose` prints every classifier via `ins()` into a width-fitted table, so
// a 150 KB preamble string there blows the verbose output up to megabytes.)
pub type LatexFragmentType {
  LatexFile
}

type Fragment(z) =
  ds.OutputFragment(LatexFragmentType, z)

type OL =
  List(OutputLine)

pub type LatexSplitterError {
  EmptyDocument
}

fn our_splitter(
  di: DocumentInfo,
  gran: Granularity,
  root: VXML,
) -> Result(#(List(Fragment(VXML)), ds.Feedback), LatexSplitterError) {
  let blame = Ext([], "latex_splitter")
  build_latex_files(root, di, gran)
  |> list.map(fn(pc) {
    let #(path, content) = pc
    let lines =
      content |> string.split("\n") |> list.map(fn(l) { Line(blame, l) })
    ds.OutputFragment(LatexFile, path, T(blame, lines))
  })
  |> fn(fragments) { Ok(#(fragments, ds.NoFeedback)) }
}

fn our_emitter(
  fragment: Fragment(VXML),
) -> Result(#(Fragment(OL), ds.Feedback), String) {
  let blame = Ext([], "latex_emitter")
  let lines = case fragment.payload {
    T(_, ls) -> list.map(ls, fn(l) { OutputLine(blame, 0, l.content) })
    V(_, _, _, _) -> []
  }
  Ok(#(ds.OutputFragment(..fragment, payload: lines), ds.NoFeedback))
}

// Copy the course's `public/figures/` next to the emitted `.tex`, so the
// `figures/<name>` paths in `\includegraphics` resolve when compiling from the
// output directory (and the .tex + images stay a self-contained bundle).
// Returns how many files were copied.
fn copy_figures(course_dir: String, output_dir: String) -> Int {
  let src = course_dir <> "/public/figures"
  let dst = output_dir <> "figures"
  case simplifile.is_directory(src) {
    Ok(True) -> {
      let _ = simplifile.create_directory_all(dst)
      case simplifile.read_directory(src) {
        Ok(files) ->
          list.fold(files, 0, fn(n, f) {
            case simplifile.copy_file(src <> "/" <> f, dst <> "/" <> f) {
              Ok(_) -> n + 1
              Error(_) -> n
            }
          })
        Error(_) -> 0
      }
    }
    _ -> 0
  }
}

pub fn render(
  arguments: ds.ParsedCLIArguments,
  course_dir: String,
  granularity: Granularity,
) -> Nil {
  let #(output_dir_local_path, arguments) = case arguments.output_dir {
    None -> #("latex", arguments)
    Some(x) -> #(x, ds.ParsedCLIArguments(..arguments, output_dir: None))
  }
  let assert None = arguments.input_dir
  let assert None = arguments.output_dir

  let parent = course_dir <> "/wly/__parent.wly"
  case simplifile.read(parent) {
    Error(_) -> {
      io.println("unable to read '" <> parent <> "'")
      io.println("")
    }
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
      let output_dir = "./" <> course_dir <> "/" <> output_dir_local_path <> "/"

      let parameters =
        ds.RendererParameters(
          input_dir: "./" <> course_dir <> "/wly/",
          output_dir: output_dir,
          prettifier_behavior: ds.PrettifierOff,
        )
        |> ds.amend_renderer_parameters_by_arguments(arguments)

      let options =
        ds.vanilla_options()
        |> ds.amend_renderer_options_by_arguments(arguments)

      let renderer =
        ds.Renderer(
          assembler: wd.default_writerly_assembler(_, options),
          parser: wd.default_writerly_parser,
          filterer: ds.default_filterer(_, options, []),
          pipeline: latex_pipeline.latex_pipeline(),
          splitter: our_splitter(document_info, granularity, _),
          emitter: our_emitter,
          writer: ds.default_writer,
          prettifier: ds.default_prettier_prettifier,
        )

      // Snapshot the `.tex` files that existed BEFORE we wipe the directory, so
      // we can report which ones are `created` / `deleted` this run (LBP-style),
      // relative to the previous run rather than to the empty dir. We track only
      // `.tex` — figures + pdflatex leftovers (.aux/.toc/.log/.pdf) aren't the
      // renderer's own artifacts and would just be noise.
      let previously_existing = case simplifile.get_files(output_dir) {
        Ok(files) ->
          files
          |> list.filter(string.ends_with(_, ".tex"))
          |> list.map(drop_dot_slash)
        Error(_) -> []
      }

      // start from a clean output directory: remove any previous run's files
      // (.tex, plus pdflatex leftovers .toc/.aux/.log/.out/.pdf, and figures/ —
      // it gets re-copied below, so source image changes are picked up).
      // Ignore the error when the directory does not exist yet (first run).
      // Log the effective shell command in the same bullet style as the render
      // stages, so it reads as the first step (before `• assembling...`).
      io.println(
        "• running 'rm -r "
        <> course_dir
        <> "/"
        <> output_dir_local_path
        <> "/*'",
      )
      let _ = simplifile.clear_directory(output_dir)

      case ds.run_renderer(renderer, parameters, options) {
        Error(error) -> {
          io.println("latex renderer error: " <> ins(error))
          io.println("")
        }
        Ok(written_paths) -> {
          let n_figs = copy_figures(course_dir, output_dir)

          // `written_paths` are relative to `output_dir`; normalize to the same
          // form as `previously_existing` so the set difference is meaningful.
          let written =
            written_paths
            |> list.map(fn(p) { drop_dot_slash(output_dir <> p) })

          let created =
            written
            |> list.filter(fn(w) { !list.contains(previously_existing, w) })
          let deleted =
            previously_existing
            |> list.filter(fn(e) { !list.contains(written, e) })

          // Announce created / deleted files (LBP-style). Files that persist
          // across runs stay silent. `deleted` files are already gone (the rm
          // above removed them); we only need to report them.
          list.each(created, fn(p) { io.println("created " <> p) })
          case created {
            [] -> Nil
            _ -> io.println("")
          }

          list.each(deleted, fn(p) { io.println("deleted " <> p) })
          case deleted {
            [] -> Nil
            _ -> io.println("")
          }

          // Note: `run_renderer`'s writer already reports every .tex it wrote
          // (a count, or one line per file under `--artifacts`), main.tex
          // included. So don't re-announce "wrote main.tex" here — that reads
          // as a stray duplicate. Just point at the compile target (useful in
          // modular mode, where many .tex files exist but only main.tex
          // compiles) and note the figures, which are copied outside the writer
          // and so are not in its report.
          let figs_note = case n_figs {
            0 -> ""
            _ -> " (+ " <> int.to_string(n_figs) <> " figures copied)"
          }
          io.println(
            "compile target: " <> output_dir <> "main.tex" <> figs_note,
          )
          io.println("")
        }
      }
    }
  }
}
