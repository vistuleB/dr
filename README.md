# PDFLaTeX

On MacOS, install pdflatex with `brew install --cask basictex`

Convert LaTeX to pdf with `pdflatex file.tex`


# Shared `app.css` and `app.js`

How to create symlinks of shared css and js for new course such as `235A`

1. `cd` into project root
2. `ln -s ../../shared/app.css 235A/public/app.css`
3. `ln -s ../../shared/app.js 235A/public/app.js`
