#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vim=${VIM:-vim}
plug=${ONESIMUS_VIM_PLUG:-"$HOME/.vim/autoload/plug.vim"}

if [ ! -r "$plug" ]; then
  echo "SKIP migration: vim-plug is not available"
  exit 0
fi

fixture=$(mktemp -d "${TMPDIR:-/tmp}/onesimus migration.XXXXXX")
trap 'rm -rf "$fixture"' EXIT HUP INT TERM
plugins=$fixture/plugins
mkdir -p "$plugins/ale" "$plugins/nerdtree"

git -C "$plugins/ale" init -q
git -C "$plugins/ale" remote add origin https://github.com/w0rp/ale.git

git -C "$plugins/nerdtree" init -q
git -C "$plugins/nerdtree" remote add origin https://example.com/my/nerdtree.git
git -C "$plugins/nerdtree" remote add upstream \
  https://github.com/scrooloose/nerdtree.git

HOME=$fixture ONESIMUS_VIM_PLUG=$plug ONESIMUS_PLUGIN_HOME=$plugins \
  "$vim" \
  --cmd 'let g:startify_disable_at_vimenter=1 | let g:onesimus_usage_enabled=0' \
  -Nu "$repo/init.vim" -i NONE -n -es -c 'qa!'

test "$(git -C "$plugins/ale" config --get remote.origin.url)" = \
  https://github.com/dense-analysis/ale.git
test "$(git -C "$plugins/nerdtree" config --get remote.origin.url)" = \
  https://example.com/my/nerdtree.git
test "$(git -C "$plugins/nerdtree" config --get remote.upstream.url)" = \
  https://github.com/scrooloose/nerdtree.git

echo "PASS migration"
