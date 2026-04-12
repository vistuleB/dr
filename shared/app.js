// List operations
document.querySelectorAll("ol.list").forEach((list) => {
  const prefix = list.dataset.prefix;
  const suffix = list.dataset.suffix;

  if (prefix) {
    list.style.setProperty("--marker-prefix", `"${prefix}"`);
  } else {
    // check if suffix exist then set prefix to empty string to override default `(` prefix
    // this handle list markers such as `1.`, `i.` etc where only suffix exist and there shouldn't be any prefix
    if (suffix) list.style.setProperty("--marker-prefix", `""`);
  }
  if (suffix) list.style.setProperty("--marker-suffix", `"${suffix}"`);
});
