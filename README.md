# PDFLaTeX

On MacOS, install pdflatex with `brew install --cask basictex`

Convert LaTeX to pdf with `pdflatex file.tex`


# Add a shared asset to a course

As an example, say we would like to add `mathjax_setup.js` to course `235A`. We would follow these steps

1. `cd` into project root
2. `ln -s ../../shared/mathjax_setup.js 235A/public/mathjax_setup.js`

# Setting Environment

Create a `.env` file at the root of the project

```
COURSE=235A
OFFLINE_MODE=true
MATHJAX_VERSION=3
```
