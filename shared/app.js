// List operations
document.querySelectorAll("ol.list").forEach((list) => {
  const markerAlign = list.dataset.listMarkerAlign;
  const markerGap = list.dataset.listMarkerGap;
  const markerFontFamily = list.dataset.listMarkerFontFamily;
  const markerFontStyle = list.dataset.listMarkerFontStyle;
  const markerFontWeight = list.dataset.listMarkerFontWeight;
  const markerPrefix = list.dataset.listMarkerPrefix;
  const markerSuffix = list.dataset.listMarkerSuffix;
  const indentLeft = list.dataset.listIndentLeft;
  const indentRight = list.dataset.listIndentRight;
  const itemsGap = list.dataset.listItemsGap;

  // Set marker props
  if (markerPrefix) {
    list.style.setProperty("--list-marker-prefix", `"${markerPrefix}"`);
  } else {
    // check if suffix exist then set prefix to empty string to override default `(` prefix
    // this handle list markers such as `1.`, `i.` etc where only suffix exist and there shouldn't be any prefix
    if (markerSuffix) list.style.setProperty("--list-marker-prefix", `""`);
  }
  if (markerSuffix)
    list.style.setProperty("--list-marker-suffix", `"${markerSuffix}"`);

  if (markerGap) list.style.setProperty("--list-marker-gap", `${markerGap}`);

  if (markerAlign) {
    switch (markerAlign) {
      case "right":
        list.style.setProperty("--list-marker-align", "end");
        break;
      case "left":
        list.style.setProperty("--list-marker-align", "start");
        break;
    }
  }

  if (markerFontStyle)
    list.style.setProperty("--list-marker-font-style", `${markerFontStyle}`);

  if (markerFontWeight)
    list.style.setProperty("--list-marker-font-weight", `${markerFontWeight}`);

  if (markerFontFamily) {
    switch (markerFontFamily) {
      case "serif":
        list.style.setProperty(
          "--list-marker-font-family",
          `${markerFontFamily}`,
        );
        break;
      case "sans-serif":
        list.style.setProperty(
          "--list-marker-font-family",
          `${markerFontFamily}`,
        );
        break;
      case "cursive":
        list.style.setProperty(
          "--list-marker-font-family",
          `${markerFontFamily}`,
        );
        break;
      case "system-ui":
        list.style.setProperty(
          "--list-marker-font-family",
          `${markerFontFamily}`,
        );
        break;
      default:
        list.style.setProperty(
          "--list-marker-font-family",
          `"${markerFontFamily}"`,
        );
    }
  }

  // Set rest of the properties
  if (indentLeft) list.style.setProperty("--list-indent-left", `${indentLeft}`);
  if (indentRight)
    list.style.setProperty("--list-indent-right", `${indentRight}`);
  if (itemsGap) list.style.setProperty("--list-items-gap", `${itemsGap}`);
});

let inputBuffer = "";
let bufferTimeout;

const meta = document.querySelector('meta[name="course"]');
const course = meta ? meta.content : null;

// chapter navigation functions
const navigateToChapter = (elementId) => {
  const element = document.getElementById(elementId);
  if (element && element.tagName === "A" && element.href) {
    window.location.href = element.href;
  }
  return;
};

const navigateWithKey = (num) => {
  if (typeof chapterMap === "undefined") return undefined;
  const section = chapterMap[num];
  if (section === undefined) return undefined;
  return `${num}-${section}.html`;
};

const getMatchingChapters = (prefix) => {
  if (typeof chapterMap === "undefined") return null;
  return Object.keys(chapterMap).filter((key) => key.startsWith(prefix));
};

const onKeyDown = (e) => {
  const activeElement = document.activeElement;
  const isInputFocused =
    activeElement &&
    (activeElement.tagName === "INPUT" ||
      activeElement.tagName === "TEXTAREA" ||
      activeElement.isContentEditable);

  if (isInputFocused) return;

  // PAGE NAVIGATION
  if (e.key === "ArrowLeft") {
    e.preventDefault();
    navigateToChapter("prev-page");
  }

  if (e.key === "ArrowRight") {
    e.preventDefault();
    navigateToChapter("next-page");
  }

  // NUMBER INPUT BUFFER (multi-digit chapter selection)
  if (/^\d$/.test(e.key)) {
    inputBuffer += e.key;

    clearTimeout(bufferTimeout);

    // "0" always navigates to index immediately
    if (inputBuffer === "0") {
      window.location.href = "index.html";
      inputBuffer = "";
      return;
    }

    const matches = getMatchingChapters(inputBuffer);

    // No valid chapter can start with this buffer — discard immediately
    if (matches !== null && matches.length === 0) {
      inputBuffer = "";
      return;
    }

    // Exactly one chapter matches and it's an exact match — no need to wait
    if (
      matches !== null &&
      matches.length === 1 &&
      matches[0] === inputBuffer
    ) {
      const route = navigateWithKey(Number(inputBuffer));
      if (route) window.location.href = route;
      inputBuffer = "";
      return;
    }

    bufferTimeout = setTimeout(() => {
      const num = Number(inputBuffer);

      if (num === 0) {
        window.location.href = "/";
        inputBuffer = "";
        return;
      }

      const route = navigateWithKey(num);

      // do nothing if invalid route
      if (!route) {
        inputBuffer = "";
        return;
      }

      window.location.href = route;
      inputBuffer = "";
    }, 500);
  }
};

document.addEventListener("keydown", onKeyDown);

// ---------------------------------------------------------------------------
// Author mode (`--local`): source-linking tooltips.
//
// The pipeline (gated on `author_mode`) injects `t-3003` spans that carry a
// source `path:line:col`. `local.css` reveals them on hover; here we make them
// clickable: a click POSTs to the dev server's `/log-event` endpoint (see
// vite.config.js), which opens the file in the editor (`code --goto`) or the
// underlying asset (`open`, for image `t-3003-i` tooltips). No `t-3003` spans
// on the page means we are not in author mode, so this is a no-op for the
// normal (non-`--local`) build, whose pages don't even load this behavior's
// `local.css`.
// ---------------------------------------------------------------------------
const sendCmdTo3003 = (command) => {
  const payload = { cmd: command };
  const url =
    window.location.protocol === "file:"
      ? "http://localhost:3003/log-event"
      : "/log-event";
  fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
};

const authorModeInit = () => {
  const tooltips = document.getElementsByClassName("t-3003");

  if (tooltips.length <= 0) return; // no tooltips == not author mode

  for (const t of tooltips) {
    if (t.classList.contains("t-3003-i")) {
      const urls = t.getElementsByClassName("t-3003-i-url");
      for (const u of urls) {
        u.addEventListener("click", (e) => {
          e.preventDefault();
          e.stopPropagation();
          sendCmdTo3003("open " + u.innerHTML);
        });
      }
    } else {
      t.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        sendCmdTo3003("code --goto " + t.innerHTML);
      });
    }
  }
};

authorModeInit();
