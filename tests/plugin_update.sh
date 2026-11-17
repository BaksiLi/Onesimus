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
{
  printf '%s\n' \
    'set nocompatible' \
    'let s:plugin_root = $ONESIMUS_STUB_PLUGIN_ROOT' \
    "let g:plugs = {'present': {'uri': 'https://example.invalid/present.git', 'dir': s:plugin_root.'/present'}}" \
    "let g:plugs['vim-clap'] = {'dir': \$ONESIMUS_STUB_CLAP_DIR, 'do': './install.sh'}" \
    "let g:plugs['jieba.vim'] = {'dir': '', 'do': ':call OnesimusJiebaInstall()'}" \
    "if \$ONESIMUS_STUB_MODE ==# 'missing'" \
    "  let g:plugs.absent = {'uri': 'https://example.invalid/absent.git', 'dir': s:plugin_root.'/absent'}" \
    'endif' \
    'function! OnesimusPluginSnapshot() abort' \
    "  call writefile(['snapshot'], \$ONESIMUS_STUB_LOG, 'a')" \
    "  if \$ONESIMUS_STUB_MODE ==# 'snapshot-error' | throw 'snapshot refused' | endif" \
    'endfunction' \
    'function! OnesimusTestPlugUpdate(args) abort' \
    "  for name in ['vim-clap', 'jieba.vim']" \
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
  clap_dir=
  report="$case_dir/update report"
  calls="$case_dir/stub calls"
  vim_log="$case_dir/vim output"

  mkdir -p "$plugin_root/present"
  : >"$calls"

  case $mode in
    clap-build|clap-failed)
      clap_dir="$plugin_root/vim-clap"
      mkdir -p "$clap_dir"
      cat >"$clap_dir/install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' clap-install >>"$ONESIMUS_STUB_LOG"
if [ "$ONESIMUS_STUB_MODE" = clap-failed ]; then
  echo 'fixture build failed'
  exit 1
fi
mkdir -p bin
: >bin/maple
chmod +x bin/maple
EOF
      chmod +x "$clap_dir/install.sh"
      ;;
  esac

  if ONESIMUS_UPDATE_REPORT="$report" \
      ONESIMUS_STUB_LOG="$calls" \
      ONESIMUS_STUB_MODE="$mode" \
      ONESIMUS_STUB_PLUGIN_ROOT="$plugin_root" \
      ONESIMUS_STUB_CLAP_DIR="$clap_dir" \
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

  [ "$(sed -n '1p' "$calls")" = snapshot ] \
    || fail "$case_name did not snapshot before changing plugins" "$calls"
  if [ "$mode" = snapshot-error ]; then
    [ "$(wc -l <"$calls" | tr -d ' ')" = 1 ] \
      || fail "$case_name changed plugins after a failed snapshot" "$calls"
    return
  fi
  [ "$(sed -n '2p' "$calls")" = upgrade ] \
    || fail "$case_name did not invoke PlugUpgrade after the snapshot" "$calls"
  [ "$(sed -n '3p' "$calls")" = 'update --sync' ] \
    || fail "$case_name did not invoke PlugUpdate --sync" "$calls"
  [ "$(sed -n '4p' "$calls")" = "$expected_reconcile" ] \
    || fail "$case_name invoked the wrong reconciliation command" "$calls"
  [ -z "$(sed -n '5p' "$calls")" ] \
    || fail "$case_name invoked unexpected plugin commands" "$calls"
}

run_case success success zero '3 plugins synchronized'
run_case plugin-error error nonzero 'x failed to update present'
run_case missing-plugin missing nonzero 'missing plugin: absent'
run_case snapshot-error snapshot-error nonzero 'snapshot refused'
run_case clap-build clap-build zero '3 plugins synchronized' clap-install
run_case clap-failed clap-failed nonzero 'vim-clap build: fixture build failed' clap-install

echo 'PASS: plugin updater reports synchronization and reconciliation failures'
