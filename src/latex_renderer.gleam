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
        // standalone appendix units (outside the numbered chapter sequence):
        // an unnumbered \chapter* that still appears in the TOC + outline.
        "Exercises" | "Bibliography" -> {
          let title = find_attr(attrs, "title") |> option.unwrap(tag)
          "\n\n\\chapter*{"
          <> emit_mixed(title)
          <> "}\n\\addcontentsline{toc}{chapter}{"
          <> emit_mixed(title)
          <> "}\n"
          <> label_of(attrs)
          <> nodes_to_latex(children, ctx)
          <> "\n"
        }
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
          "\\href{" <> escape_url(href) <> "}{" <> nodes_to_latex(children, ctx) <> "}"
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
  <> "  pdftitle={" <> escape_prose(di.title) <> "},\n"
  <> "  pdfauthor={" <> escape_prose(di.lecturer) <> "}\n"
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
  <> "\\date{" <> emit_mixed(di.date) <> "}\n"
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
    V(_, _, _, children) -> list.flat_map(children, collect_eq_labels(_, math_tok))
  }
}

fn emit_document(root: VXML, di: DocumentInfo) -> String {
  let assert Ok(tok) = regexp.from_string(token_pattern)
  let assert Ok(math_tok) = regexp.from_string(math_token_pattern)
  let assert Ok(amp_tok) = regexp.from_string("&[^&]*&")
  let eq_numbers =
    collect_eq_labels(root, math_tok)
    |> list.index_map(fn(name, i) { #(name, i + 1) })
    |> dict.from_list
  let base_ctx = Ctx(dict.new(), eq_numbers, tok, math_tok, amp_tok)
  let footnotes = gather_footnotes(root, base_ctx)
  let ctx = Ctx(footnotes, eq_numbers, tok, math_tok, amp_tok)
  let body = node_to_latex(root, ctx)
  preamble(di)
  // `\pdfbookmark[0]{Contents}{toc}` adds a top-level, unnumbered PDF outline
  // entry for the table of contents itself (which \tableofcontents does not
  // bookmark on its own), pointing at the TOC page.
  <> "\n\\begin{document}\n\\maketitle\n"
  <> "\\pdfbookmark[0]{Contents}{toc}\n"
  <> "\\tableofcontents\n\n"
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
        _ -> {
          let n_figs = copy_figures(course_dir, output_dir)
          let figs_note = case n_figs {
            0 -> ""
            _ -> " (+ " <> int.to_string(n_figs) <> " figures)"
          }
          io.println("\nwrote " <> output_dir <> filename <> figs_note <> "\n")
        }
      }
    }
  }
}
