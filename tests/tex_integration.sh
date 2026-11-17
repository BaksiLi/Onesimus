#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if ! command -v latexmk >/dev/null 2>&1; then
  echo 'SKIP: latexmk unavailable for real build tests'
  exit 0
fi
fixture=$(mktemp -d "${TMPDIR:-/tmp}/onesimus-tex-integration.XXXXXX")
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
export ONESIMUS_TEST_PROJECT="$fixture"
export XDG_STATE_HOME="$fixture/state"
export VIMRCDIR="$repo"
export MYVIMDOT="$repo/init.vim"
"${VIM:-vim}" -Nu "$repo/init.vim" -i NONE -n -T xterm -V1"$fixture/vim.log" \
  --cmd 'let g:startify_disable_at_vimenter = 1 | let g:onesimus_usage_enabled = 0 | let g:onesimus_refresh_interval = 100' \
  -S "$repo/tests/support/tex_integration.vim" >"$fixture/output" 2>&1 || {
    cat "$fixture/output"
    exit 1
  }

if [ ! -f "$fixture/passed" ]; then
  cat "$fixture/output"
  echo 'FAIL: integration script did not reach its final assertions'
  exit 1
fi
