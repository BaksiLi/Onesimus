#!/bin/sh
set -eu

package=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$package"
python_bin=${PYTHON:-python3}
vim_bin=${WEBPREVIEW_TEST_VIM:-vim}
export PYTHONDONTWRITEBYTECODE=1 PYTHON="$python_bin"

case ${1:-} in
  '') ;;
  --full)
    for tool in node npm pdflatex synctex latexmk latexdiff lualatex; do
      command -v "$tool" >/dev/null || { echo "Required for --full: $tool" >&2; exit 1; }
    done
    if ! command -v pdftotext >/dev/null && ! command -v gs >/dev/null; then
      echo 'Required for --full: pdftotext or gs' >&2
      exit 1
    fi
    ;;
  *) echo 'Usage: sh tests/run.sh [--full]' >&2; exit 2 ;;
esac

"$vim_bin" -Nu NONE -i NONE -n -es -S tests/vim.vim
"$python_bin" -m unittest discover -s tests
node tests/markdown-engine.mjs

if [ "${1:-}" = --full ]; then
  work=$(mktemp -d "${TMPDIR:-/tmp}/webpreview-tests.XXXXXX")
  trap '"$python_bin" -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$work"' EXIT HUP INT TERM
  node tests/remark-annotation.mjs
  node tests/markdown-build.mjs
  node tests/commonmark.mjs
  node tests/browser.mjs
  node tests/markdown.browser.mjs
  node web/build-assets.mjs --engine markdown-it --output "$work/markdown-it.zip"
  node tests/markdown-engine.mjs "$work/markdown-it.zip"
  node tests/commonmark.mjs "$work/markdown-it.zip"
  MARKDOWN_ASSETS="$work/markdown-it.zip" node tests/markdown.browser.mjs
fi
