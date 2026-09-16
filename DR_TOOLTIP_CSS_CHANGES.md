# DR source-tooltip CSS fixes

## Scope

These changes concern the source-location tooltips produced by `dr` when
rendering with `--local`. The tooltips highlight source text and expose a
clickable source location without changing the layout of the document.

Edit **`dr/shared/local.css`**. The course stylesheet
`dr/119B/public/local.css` is a symlink to `../../shared/local.css`, so no HTML
regeneration is needed for these CSS changes. Reload the page after editing.

No pipeline, HTML markup, or JavaScript changes were required.

## 1. Reveal tooltips without toggling their display

Previously, `.t-3003` had `display: none`, and the hover rules changed it to
`display: block`. Text could shift when a tooltip appeared, particularly
around inline boundaries. Keeping the absolutely positioned box present and
changing its visibility resolved the observed movement.

In the base `.t-3003` rule, replace:

```css
display: none;
```

with:

```css
display: block;
visibility: hidden;
```

Keep the existing `position: absolute`, `opacity: 0`, positioning, styling,
and opacity transition.

In each tooltip-reveal rule, replace `display: block` with
`visibility: visible`, keeping `opacity: 1`:

```css
.t-3003-c:hover .t-3003 {
  visibility: visible;
  opacity: 1;
}

figure:hover > .t-3003 {
  visibility: visible;
  opacity: 1;
}

.math-block:hover > .t-3003 {
  visibility: visible;
  opacity: 1;
  position: absolute;
  left: 50%;
  top: -3.5em;
}
```

Update the mobile-dismiss override as well. Replace
`display: none !important` with `visibility: hidden !important`:

```css
html.tt-hide .t-3003 {
  visibility: hidden !important;
  opacity: 0 !important;
}
```

This preserves the existing JavaScript behavior that adds `tt-hide` after
tapping outside a tooltip or its host.

## 2. Keep display-math layout properties constant across hover

Previously, hovering a math block with a tooltip changed its `display` to
`flow-root` and its `overflow` to `visible`. Those properties affect layout
and clipping, so they should be established before hover.

Keep the existing positioning rule:

```css
.math-block {
  position: relative;
}
```

Add a non-hover rule for math blocks containing a source tooltip:

```css
.math-block:has(> .t-3003) {
  display: flow-root;
  overflow: visible;
}
```

Reduce the corresponding hover-highlight rule to:

```css
.math-block:hover:has(> .t-3003) {
  background-color: #bdf;
}
```

The tooltip can extend outside the math block, while the block's display and
overflow properties remain unchanged during hover. This does mean that these
author-mode math blocks use visible overflow even while not hovered, instead
of the ordinary stylesheet's overflow settings.

## 3. Prevent the green highlight from encroaching on neighboring lines

The text highlight previously used:

```css
border-radius: 10px;
box-shadow: 0 0 0 5px #bfb;
```

The 5px spread extended the green highlight above and below the text, making
it encroach on the preceding line in multiline chapter titles.

Replace it with two horizontal shadows and a smaller corner radius. The
complete highlight rule becomes:

```css
.t-3003-c:hover,
.t-3003-c:has(.t-3003:hover) {
  background-color: #bfb;
  border-radius: 3px;
  box-shadow: -3px 0 0 #bfb, 3px 0 0 #bfb;
}
```

The highlight extends horizontally without the previous 5px vertical spread.
No font size, line-height, margin, or padding changes are needed.

## Verification

The changes were applied manually and confirmed to work in the browser:

- Revealing source tooltips no longer causes the observed text shifting.
- Display-math layout properties no longer change on hover.
- The green highlight no longer encroaches on the line above as reported.

For subsequent testing, check ordinary prose, inline math, multiline chapter
titles, display equations, image tooltips, and touch-device dismissal. Also
check wide equations because the author-mode overflow policy is now constant.
