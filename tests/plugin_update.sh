#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vim_bin=${ONESIMUS_TEST_VIM:-$(command -v vim 2>/dev/null || true)}

if [ -z "$vim_bin" ] || [ ! -x "$vim_bin" ]; then
  echo "FAIL: Vim is not executable: ${vim_bin:-not found}" >&2
  exit 2
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/onesimus-plugin-update.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

# Deliberately keep the fixture below a path containing spaces and a quote: the
# update entry point is also used by install.sh with arbitrary checkout paths.
fixture="$work/update cases with a 'quote'"
mkdir -p "$fixture"
vimrc="$fixture/stub vimrc.vim"
stub_runtime="$fixture/stub runtime"
mkdir -p "$stub_runtime/autoload"

{
  printf '%s\n' \
    'function! plug#load(name) abort' \
    "  execute 'set runtimepath^='.fnameescape(g:plugs[a:name].dir)" \
    'endfunction'
} >"$stub_runtime/autoload/plug.vim"

{
  printf '%s\n' \
    'set nocompatible' \
    "execute 'set runtimepath^='.fnameescape(\$ONESIMUS_STUB_RUNTIME)" \
    'let s:plugin_root = $ONESIMUS_STUB_PLUGIN_ROOT' \
    "let g:plugs = {'present': {'uri': 'https://example.invalid/present.git', 'dir': s:plugin_root.'/present'}}" \
    "let g:plugs['vim-clap'] = {'dir': '', 'do': './install.sh'}" \
    "let g:plugs['markdown-preview.nvim'] = {'dir': \$ONESIMUS_STUB_MARKDOWN_DIR, 'do': ':call mkdp#util#install_sync()'}" \
    "let g:plugs['jieba.vim'] = {'dir': '', 'do': ':call OnesimusJiebaInstall()'}" \
    "if \$ONESIMUS_STUB_MODE ==# 'missing'" \
    "  let g:plugs.absent = {'uri': 'https://example.invalid/absent.git', 'dir': s:plugin_root.'/absent'}" \
    'endif' \
    'function! OnesimusTestPlugUpdate(args) abort' \
    "  for name in ['vim-clap', 'markdown-preview.nvim', 'jieba.vim']" \
    "    if !has_key(g:plugs[name], 'do') | throw 'update helper removed '.name.' hook' | endif" \
    '  endfor' \
    "  call writefile(['update '.a:args], \$ONESIMUS_STUB_LOG, 'a')" \
    '  enew' \
    '  setlocal buftype=nofile' \
    "  if \$ONESIMUS_STUB_MODE ==# 'error'" \
    "    call setline(1, ['[Plugins]', 'x failed to update present'])" \
    '  else' \
    "    call setline(1, ['[Plugins]', '- present: OK'])" \
    '  endif' \
    'endfunction' \
    'command! PlugUpgrade call writefile(['"'"'upgrade'"'"'], $ONESIMUS_STUB_LOG, '"'"'a'"'"')' \
    'command! -nargs=* PlugUpdate call OnesimusTestPlugUpdate(<q-args>)'
} >"$vimrc"

fail() {
  echo "FAIL: $1" >&2
  if [ -n "${2:-}" ] && [ -s "$2" ]; then
    sed 's/^/  /' "$2" >&2
  fi
  exit 1
}

run_case() {
  case_name=$1
  mode=$2
  expected_exit=$3
  expected_detail=$4
  expected_reconcile=${5:-}
  case_dir="$fixture/$case_name"
  plugin_root="$case_dir/plugin home"
  markdown_dir=
  markdown_actual=
  report="$case_dir/update report"
  calls="$case_dir/stub calls"
  vim_log="$case_dir/vim output"

  mkdir -p "$plugin_root/present"
  : >"$calls"

  case $mode in
    markdown-current|markdown-stale)
      markdown_dir="$plugin_root/markdown-preview.nvim"
      mkdir -p "$markdown_dir/autoload/mkdp"
      if [ "$mode" = markdown-current ]; then
        markdown_expected=0.0.10
        markdown_actual=' 0.0.10 '
      else
        markdown_expected=0.0.11
        markdown_actual=0.0.10
      fi
      printf '{"version":"%s"}\n' "$markdown_expected" >"$markdown_dir/package.json"
      {
        printf '%s\n' \
          'function! mkdp#util#install_sync(...) abort' \
          "  call writefile(['markdown-install'], \$ONESIMUS_STUB_LOG, 'a')" \
          'endfunction' \
          'function! mkdp#util#pre_build_version() abort' \
          '  return $ONESIMUS_STUB_MARKDOWN_ACTUAL' \
          'endfunction'
      } >"$markdown_dir/autoload/mkdp/util.vim"
      ;;
  esac

  if ONESIMUS_UPDATE_REPORT="$report" \
      ONESIMUS_STUB_LOG="$calls" \
      ONESIMUS_STUB_MODE="$mode" \
      ONESIMUS_STUB_PLUGIN_ROOT="$plugin_root" \
      ONESIMUS_STUB_MARKDOWN_DIR="$markdown_dir" \
      ONESIMUS_STUB_MARKDOWN_ACTUAL="$markdown_actual" \
      ONESIMUS_STUB_RUNTIME="$stub_runtime" \
      "$vim_bin" -Nu "$vimrc" -i NONE -n -es \
      -S "$repo/scripts/update_plugins.vim" >"$vim_log" 2>&1; then
    status=0
  else
    status=$?
  fi

  case $expected_exit in
    zero)
      [ "$status" -eq 0 ] || fail "$case_name exited with status $status" "$vim_log"
      ;;
    nonzero)
      [ "$status" -ne 0 ] || fail "$case_name unexpectedly succeeded" "$vim_log"
      ;;
    *)
      fail "invalid expected exit mode: $expected_exit"
      ;;
  esac

  [ -f "$report" ] || fail "$case_name did not write an update report" "$vim_log"
  [ "$(sed -n '1p' "$report")" = "$( [ "$expected_exit" = zero ] && printf OK || printf ERROR )" ] \
    || fail "$case_name wrote the wrong report status" "$report"
  [ "$(sed -n '2p' "$report")" = "$expected_detail" ] \
    || fail "$case_name wrote the wrong report detail" "$report"
  [ -z "$(sed -n '3p' "$report")" ] \
    || fail "$case_name wrote unexpected extra report lines" "$report"

  [ "$(sed -n '1p' "$calls")" = upgrade ] \
    || fail "$case_name did not invoke PlugUpgrade first" "$calls"
  [ "$(sed -n '2p' "$calls")" = 'update --sync' ] \
    || fail "$case_name did not invoke PlugUpdate --sync" "$calls"
  [ "$(sed -n '3p' "$calls")" = "$expected_reconcile" ] \
    || fail "$case_name invoked the wrong reconciliation command" "$calls"
  [ -z "$(sed -n '4p' "$calls")" ] \
    || fail "$case_name invoked unexpected plugin commands" "$calls"
}

run_case success success zero '4 plugins synchronized'
run_case plugin-error error nonzero 'x failed to update present'
run_case missing-plugin missing nonzero 'missing plugin: absent'
run_case markdown-current markdown-current zero '4 plugins synchronized' markdown-install
run_case markdown-stale markdown-stale nonzero \
  'markdown-preview.nvim build: preview binary version mismatch: expected 0.0.11, got 0.0.10' \
  markdown-install

echo 'PASS: plugin updater reports synchronization and reconciliation failures'
