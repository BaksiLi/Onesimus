#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vim_bin=${ONESIMUS_TEST_VIM:-vim}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/onesimus-test_root.XXXXXX")
trap 'rm -rf "$fixture"' EXIT HUP INT TERM

runtime_root=$fixture/test_'*'root
sibling_root=$fixture/test_axroot
ln -s "$repo" "$runtime_root"
mkdir -p "$sibling_root/functions"
printf '%s\n' 'let g:onesimus_path_escape = 1' \
  >"$sibling_root/functions/sentinel.vim"

VIMRCDIR=$runtime_root \
MYVIMDOT=$runtime_root/init.vim \
  "$vim_bin" \
  --cmd 'let g:onesimus_usage_enabled=0 | let g:startify_disable_at_vimenter=1' \
  -Nu "$repo/init.vim" -i NONE -n -es \
  -c 'if exists(":OnesimusGuide") != 2 || exists(":CompileRun") != 2 || exists("g:onesimus_path_escape") | cquit | endif' \
  -c 'qa!'

echo 'PASS: runtime paths treat test_ and glob characters literally'
