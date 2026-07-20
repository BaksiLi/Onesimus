#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo"
configured_vim=${VIM:-vim}
vim_bin=$(command -v "$configured_vim" 2>/dev/null || true)
unset VIM

if [ -z "$vim_bin" ] || [ ! -x "$vim_bin" ]; then
  echo "FAIL: Vim is not executable: $configured_vim" >&2
  exit 2
fi
if [ ! -x "$repo/install.sh" ]; then
  echo 'FAIL: install.sh must be executable in the repository checkout' >&2
  exit 2
fi

case $vim_bin in
  /*) ;;
  *) vim_bin=$(CDPATH= cd -- "$(dirname -- "$vim_bin")" && pwd)/$(basename -- "$vim_bin") ;;
esac

work=$(mktemp -d "${TMPDIR:-/tmp}/onesimus-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/bin"
printf '%s\n' '#!/bin/sh' 'exec "$ONESIMUS_RUNNER_VIM" "$@"' \
  >"$work/bin/vim"
chmod +x "$work/bin/vim"

# Do not export a variable named VIM: Vim itself interprets $VIM as its runtime
# root.  A tiny executable wrapper lets shell fixtures discover the selected
# binary through PATH without changing the executable path seen by Vim.
PATH=$work/bin:$PATH
export PATH ONESIMUS_RUNNER_VIM="$vim_bin" ONESIMUS_TEST_VIM="$vim_bin"

failures=0
tests_run=0
tests_skipped=0

record_failure() {
  failures=$((failures + 1))
  echo "FAIL: $1"
  if [ -s "$2" ]; then
    sed 's/^/  /' "$2"
  fi
}

run_vim_test() {
  test_file=$1
  name=$(basename -- "$test_file" .vim)
  log=$work/$name.log
  result=

  case $name in
    ale_fix) result=/tmp/onesimus-ale-fix-result ;;
    ale_haskell) result=/tmp/onesimus-ale-haskell-result ;;
    ale_python) result=/tmp/onesimus-ale-python-result ;;
    cjk_motion) result=/tmp/onesimus-cjk-motion-result ;;
    guide) result=/tmp/onesimus-guide-result ;;
  esac
  if [ -n "$result" ]; then
    rm -f "$result"
  fi

  tests_run=$((tests_run + 1))
  printf '  %-28s ' "$name.vim"
  if [ "$name" = portable ]; then
    if (unset VIMRCDIR MYVIMDOT; "$vim_bin" -Nu "$repo/init.vim" \
        -i NONE -n -es -S "$test_file") \
        >"$log" 2>&1; then
      status=0
    else
      status=$?
    fi
  elif "$vim_bin" -Nu "$test_file" -i NONE -n -es >"$log" 2>&1; then
    status=0
  else
    status=$?
  fi

  if [ "$status" -ne 0 ]; then
    if [ -n "$result" ] && [ -s "$result" ]; then
      cat "$result" >>"$log"
    fi
    record_failure "$name.vim exited with status $status" "$log"
    return
  fi

  if [ -n "$result" ]; then
    if [ ! -s "$result" ]; then
      record_failure "$name.vim produced no result" "$log"
      return
    fi
    verdict=$(sed -n '1p' "$result")
    case $verdict in
      SKIP*)
        tests_skipped=$((tests_skipped + 1))
        echo "$verdict"
        return
        ;;
      PASS*) ;;
      *)
        printf '%s\n' "$verdict" >>"$log"
        record_failure "$name.vim reported a failure" "$log"
        return
        ;;
    esac
  fi

  echo PASS
}

run_shell_test() {
  test_file=$1
  name=$(basename -- "$test_file")
  log=$work/$name.log
  tests_run=$((tests_run + 1))
  printf '  %-28s ' "$name"

  if sh "$test_file" >"$log" 2>&1; then
    if grep -q '^SKIP' "$log"; then
      tests_skipped=$((tests_skipped + 1))
      sed -n '/^SKIP/{p;q;}' "$log"
    else
      echo PASS
    fi
  else
    status=$?
    record_failure "$name exited with status $status" "$log"
  fi
}

echo "Onesimus tests: $($vim_bin --version | sed -n '1p')"

for test_file in "$repo"/tests/*.vim; do
  run_vim_test "$test_file"
done

for test_file in "$repo"/tests/*.sh; do
  if [ "$(basename -- "$test_file")" != run.sh ]; then
    run_shell_test "$test_file"
  fi
done

if [ "$failures" -ne 0 ]; then
  echo "$failures of $tests_run tests failed ($tests_skipped skipped)." >&2
  exit 1
fi

echo "All $tests_run tests passed ($tests_skipped skipped)."
