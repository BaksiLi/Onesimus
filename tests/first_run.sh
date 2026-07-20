#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
vim_bin=${ONESIMUS_TEST_VIM:-vim}
home=$(mktemp -d "${TMPDIR:-/tmp}/onesimus-first-run.XXXXXX")
trap 'code=$?; rm -rf "$home"; exit $code' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$home/bin" "$home/fixture"
result=$home/result
curl_called=$home/curl-called
curl_args=$home/curl-args
plug_fixture=$home/fixture/plug.vim
vim_log=$home/vim.log

# This is deliberately a small API-compatible fixture rather than a copy of a
# developer's installed vim-plug.  Starting with no autoload/plug.vim proves
# that the bootstrap path invokes curl and then continues loading the config.
cat >"$plug_fixture" <<'EOF'
if exists('g:loaded_onesimus_plug_fixture')
  finish
endif
let g:loaded_onesimus_plug_fixture = 1

function! plug#begin(...) abort
  let g:plugs = {}
  command! -nargs=+ -bar Plug call plug#onesimus_register(<args>)
endfunction

function! plug#onesimus_register(repository, ...) abort
  let l:name = fnamemodify(substitute(a:repository, '\.git$', '', ''), ':t')
  let l:options = get(a:000, 0, {})
  if type(l:options) == v:t_dict && has_key(l:options, 'as')
    let l:name = l:options.as
  endif
  let g:plugs[l:name] = {'dir': expand('~/.vim/bundle/'.l:name)}
endfunction

function! plug#end() abort
  silent! delcommand Plug
  let g:onesimus_fixture_plug_end = get(g:,
        \ 'onesimus_fixture_plug_end', 0) + 1
  if g:onesimus_fixture_plug_end > 1
    command! Startify let g:onesimus_fixture_home = 1
  endif
endfunction

function! plug#onesimus_install() abort
  let g:onesimus_fixture_plug_install = 1
endfunction

command! -nargs=* -bar PlugInstall call plug#onesimus_install()
EOF

cat >"$home/bin/curl" <<'EOF'
#!/bin/sh
set -eu

printf '%s\n' "$@" >"$ONESIMUS_CURL_ARGS"
destination=
while [ "$#" -gt 0 ]; do
  case $1 in
    -fLo|-o)
      destination=$2
      shift 2
      ;;
    --create-dirs)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

test -n "$destination"
mkdir -p "$(dirname -- "$destination")"
cp "$ONESIMUS_VIM_PLUG_FIXTURE" "$destination"
: >"$ONESIMUS_CURL_CALLED"
EOF
chmod +x "$home/bin/curl"

if ! HOME=$home \
  PATH=$home/bin:$PATH \
  VIMRCDIR=$repo \
  MYVIMDOT=$repo/init.vim \
  ONESIMUS_VIM_PLUG_FIXTURE=$plug_fixture \
  ONESIMUS_CURL_CALLED=$curl_called \
  ONESIMUS_CURL_ARGS=$curl_args \
  ONESIMUS_FIRST_RUN_RESULT=$result \
    "$vim_bin" \
    --cmd 'let g:onesimus_usage_enabled=0 | let g:onesimus_home_enabled=1 | let g:startify_disable_at_vimenter=1' \
    -Nu "$repo/init.vim" -i NONE -n -es -V1"$vim_log" \
    -c 'doautocmd VimEnter' \
    -c 'sleep 20m' \
    -c 'let g:onesimus_first_run_ok = empty(v:errmsg) && get(g:, "onesimus_fixture_plug_install", 0) && get(g:, "onesimus_fixture_plug_end", 0) > 1 && get(g:, "onesimus_fixture_home", 0) && exists("#onesimus_home#VimEnter") && get(g:, "onesimus_bootstrap_ready", 0)' \
    -c 'call writefile([g:onesimus_first_run_ok ? "PASS" : printf("FAIL install=%d end=%d home=%d autocmd=%d ready=%d errmsg=%s", get(g:, "onesimus_fixture_plug_install", 0), get(g:, "onesimus_fixture_plug_end", 0), get(g:, "onesimus_fixture_home", 0), exists("#onesimus_home#VimEnter"), get(g:, "onesimus_bootstrap_ready", 0), v:errmsg)], $ONESIMUS_FIRST_RUN_RESULT)' \
    -c 'qa!'; then
  echo 'FAIL: Vim could not complete a clean first run' >&2
  sed -n '1,200p' "$vim_log" >&2
  exit 1
fi

test -f "$home/.vim/autoload/plug.vim"
test -f "$curl_called"
if test "$(sed -n '1p' "$result")" != PASS; then
  echo 'FAIL: bootstrap did not reload the completed configuration' >&2
  sed -n '1p' "$result" >&2
  sed -n '1,200p' "$vim_log" >&2
  exit 1
fi
grep -Fx -- '--connect-timeout' "$curl_args" >/dev/null
grep -Fx -- '10' "$curl_args" >/dev/null
grep -Fx -- '--max-time' "$curl_args" >/dev/null
grep -Fx -- '120' "$curl_args" >/dev/null

# A failed download must stop startup and remove the partial file.  Otherwise
# the next Vim process could source a truncated plugin manager.
failure_home=$home/failure-home
failure_bin=$home/failure-bin
failure_log=$home/failure.log
mkdir -p "$failure_home" "$failure_bin"
cat >"$failure_bin/curl" <<'EOF'
#!/bin/sh
set -eu

destination=
while [ "$#" -gt 0 ]; do
  case $1 in
    -o)
      destination=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
test -n "$destination"
mkdir -p "$(dirname -- "$destination")"
printf '%s\n' 'partial download' >"$destination"
exit 22
EOF
chmod +x "$failure_bin/curl"

if HOME=$failure_home PATH=$failure_bin:$PATH \
  VIMRCDIR=$repo MYVIMDOT=$repo/init.vim \
    "$vim_bin" \
    --cmd 'let g:onesimus_usage_enabled=0 | let g:startify_disable_at_vimenter=1' \
    -Nu "$repo/init.vim" -i NONE -n -es -V1"$failure_log" -c 'qa!' \
      >"$home/failure-output" 2>&1; then
  echo 'FAIL: a failed vim-plug download did not stop startup' >&2
  exit 1
fi
test ! -e "$failure_home/.vim/autoload/plug.vim"
test -z "$(find "$failure_home/.vim/autoload" -name 'plug.vim.*.tmp' -print)"
grep -F 'could not install vim-plug' "$failure_log" >/dev/null

echo 'PASS: first run bootstraps vim-plug from an empty HOME'
