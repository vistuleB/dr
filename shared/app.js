// List operations
document.querySelectorAll("ol.list").forEach((list) => {
  const markerAlign = list.dataset.listMarkerAlign;
  const markerGap = list.dataset.listMarkerGap;
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

  // Set rest of the properties
  if (indentLeft) list.style.setProperty("--list-indent-left", `${indentLeft}`);
  if (indentRight)
    list.style.setProperty("--list-indent-right", `${indentRight}`);
  if (itemsGap) list.style.setProperty("--list-items-gap", `${itemsGap}`);
});
