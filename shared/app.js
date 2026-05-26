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
};

const atIndexPage = window.location.pathname === "/";

const navigateWithKey = (course, num) => {
  switch (course) {
    case "MATH/STAT 235A":
      return resolveCourse235ANavigation(num);
    default:
      return undefined;
  }
};

const resolveCourse235ANavigation = (num) => {
  const section = chapterMap[num];

  if (section === undefined) return undefined;

  return `${num}-${section}.html`;
};

const onKeyDown = (e) => {
  const activeElement = document.activeElement;
  const isInputFocused =
    activeElement &&
    (activeElement.tagName === "INPUT" ||
      activeElement.tagName === "TEXTAREA" ||
      activeElement.isContentEditable);

  if (isInputFocused) return;

  // INDEX PAGE → go to first chapter
  if (atIndexPage && e.key === "ArrowRight") {
    e.preventDefault();
    window.location.href = "/1-1.html";
    return;
  }

  // PAGE NAVIGATION
  if (!atIndexPage && (e.key === "ArrowLeft" || e.key === "ArrowRight")) {
    e.preventDefault();

    if (e.key === "ArrowLeft") {
      navigateToChapter("prev-page");
    } else {
      navigateToChapter("next-page");
    }

    return;
  }

  // NUMBER INPUT BUFFER (multi-digit chapter selection)
  if (/^\d$/.test(e.key)) {
    inputBuffer += e.key;

    clearTimeout(bufferTimeout);

    bufferTimeout = setTimeout(() => {
      const num = Number(inputBuffer);

      if (num === 0) {
        window.location.href = "/";
        inputBuffer = "";
        return;
      }

      const route = navigateWithKey(course, num);

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
