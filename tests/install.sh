#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
installer=$repo/install.sh
plugin_helper=$repo/scripts/update_plugins.vim
real_git=$(command -v git)
real_vim=$(command -v vim)
work=$(mktemp -d "${TMPDIR:-/tmp}/onesimus-installer.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_same() {
  cmp -s "$1" "$2" || fail "$1 and $2 differ"
}

assert_absent() {
  test ! -e "$1" && test ! -L "$1" || fail "$1 should not exist"
}

assert_contains() {
  grep -F -- "$2" "$1" >/dev/null || {
    sed -n '1,40p' "$1" >&2
    fail "$1 does not contain: $2"
  }
}

assert_process_stopped() {
  process_pid=$1
  message=$2
  checks=0

  while kill -0 "$process_pid" 2>/dev/null; do
    process_state=$(ps -o state= -p "$process_pid" 2>/dev/null \
      | tr -d '[:space:]' || true)
    case $process_state in
      Z*) return 0 ;;
    esac
    kill -0 "$process_pid" 2>/dev/null || return 0
    test "$checks" -lt 40 || fail "$message"
    sleep 0.05
    checks=$((checks + 1))
  done
}

assert_no_staging() {
  search_root=$1
  test -z "$(find "$search_root" -name '.onesimus-install.*' -print)" \
    || fail "$search_root contains a clone staging directory"
  test -z "$(find "$tmp" -maxdepth 1 \
    \( -name 'onesimus-installer.*' \
       -o -name 'onesimus-plugins.*.log' \
       -o -name 'onesimus-plugins.*.report' \
       -o -name 'onesimus-timeout.*' \) -print)" \
    || fail 'the updater left a private installer or plugin report behind'
  test -z "$(find "$search_root" -name 'onesimus-update.lock' -print)" \
    || fail "$search_root contains a stale update lock"
}

make_fixture_repo() {
  fixture=$1
  header=$2

  mkdir -p "$fixture/scripts"
  printf '%s\n' "$header" \
    'let g:onesimus_install_fixture = 1' >"$fixture/init.vim"
  cp "$installer" "$fixture/install.sh"
  cp "$plugin_helper" "$fixture/scripts/update_plugins.vim"
  chmod +x "$fixture/install.sh"
  "$real_git" -C "$fixture" init -q
  "$real_git" -C "$fixture" config user.name 'Onesimus test'
  "$real_git" -C "$fixture" config user.email 'test@onesimus.invalid'
  "$real_git" -C "$fixture" add init.vim install.sh scripts/update_plugins.vim
  "$real_git" -C "$fixture" commit -qm 'Initial fixture'
}

write_legacy_installer() {
  destination=$1
  cat >"$destination" <<'EOF'
#!/usr/bin/env bash
# Representative Onesimos 0.1 installer: no option parser and, critically, no
# safe handoff protocol.  The current updater must never execute this file.
if [[ -n ${ONESIMUS_LEGACY_EXECUTED:-} ]]; then
  printf 'legacy installer executed\n' >"$ONESIMUS_LEGACY_EXECUTED"
fi
exit 97
EOF
  chmod +x "$destination"
}

# Prefixing assignments on run_installer calls is intentional: the helper
# forwards every failure-injection variable explicitly to the child process.
run_installer() {
  test_home=$1
  script=$2
  output=$3
  shift 3

  env \
    HOME="$test_home" \
    TMPDIR="$tmp" \
    PATH="$fake_bin:$PATH" \
    ONESIMUS_REPOSITORY="${TEST_REPOSITORY:-$upstream}" \
    ONESIMUS_VIM_BIN="$fake_bin/vim" \
    ONESIMUS_GIT_BIN="${TEST_GIT_BIN:-$real_git}" \
    REAL_GIT="$real_git" \
    FAKE_VIM_LOG="${FAKE_VIM_LOG:-}" \
    FAKE_VIM_LIFECYCLE_LOG="${FAKE_VIM_LIFECYCLE_LOG:-}" \
    FAKE_PLUGIN_FAILURE="${FAKE_PLUGIN_FAILURE:-0}" \
    FAKE_PLUGIN_HANG="${FAKE_PLUGIN_HANG:-0}" \
    FAKE_VIM_CAPABILITY_FAILURE="${FAKE_VIM_CAPABILITY_FAILURE:-0}" \
    ONESIMUS_GIT_TIMEOUT="${ONESIMUS_GIT_TIMEOUT:-180}" \
    ONESIMUS_PLUGIN_TIMEOUT="${ONESIMUS_PLUGIN_TIMEOUT:-600}" \
    ONESIMUS_INSTALL_ROOT="${ONESIMUS_INSTALL_ROOT:-}" \
    ONESIMUS_INSTALLER_STAGED="${ONESIMUS_INSTALLER_STAGED:-}" \
    ONESIMUS_INSTALL_TARGET_HINT="${ONESIMUS_INSTALL_TARGET_HINT:-}" \
    ONESIMUS_SELF_UPDATE_SENTINEL="${ONESIMUS_SELF_UPDATE_SENTINEL:-}" \
    ONESIMUS_LEGACY_EXECUTED="${ONESIMUS_LEGACY_EXECUTED:-}" \
    STUBBORN_CHILD_PID_FILE="${STUBBORN_CHILD_PID_FILE:-}" \
    INTERRUPT_READY_FILE="${INTERRUPT_READY_FILE:-}" \
    INTERRUPT_CHILD_PID_FILE="${INTERRUPT_CHILD_PID_FILE:-}" \
    CLAIM_READY_FILE="${CLAIM_READY_FILE:-}" \
    CLAIM_RELEASE_FILE="${CLAIM_RELEASE_FILE:-}" \
    FAIL_GIT_LOG="${FAIL_GIT_LOG:-}" \
    bash "$script" "$@" >"$output" 2>&1
}

publish_file() {
  fixture=$1
  path=$2
  contents=$3
  message=$4

  mkdir -p "$(dirname -- "$fixture/$path")"
  printf '%s\n' "$contents" >"$fixture/$path"
  "$real_git" -C "$fixture" add "$path"
  "$real_git" -C "$fixture" commit -qm "$message"
}

tmp="$work/private tmp"
upstream="$work/local fork upstream"
fake_bin="$work/fake bin"
home="$work/home with spaces"
root="$work/author's alternative root"
log="$work/install.log"
plugin_log="$work/plugin invocations.log"
mkdir -p "$tmp" "$upstream" "$fake_bin" "$home" "$root"

make_fixture_repo "$upstream" '" Project: Onesimus Vim'

cat >"$fake_bin/vim" <<'EOF'
#!/bin/sh
if test "${1:-}" = --version; then
  echo 'VIM - Vi IMproved 9.2 (fixture)'
  exit 0
fi

if test "${1:-}" = -Nu && test "${2:-}" = NONE; then
  test "${FAKE_VIM_CAPABILITY_FAILURE:-0}" != 1
  exit
fi

if test -n "${ONESIMUS_UPDATE_REPORT:-}"; then
  test -n "${FAKE_VIM_LOG:-}" || exit 95
  printf '%s\n' "$*" >>"$FAKE_VIM_LOG"
  if test -n "${FAKE_VIM_LIFECYCLE_LOG:-}"; then
    printf '%s\n' "sync $*" >>"$FAKE_VIM_LIFECYCLE_LOG"
  fi
  if test "${FAKE_PLUGIN_HANG:-0}" = 1; then
    sleep 20
  fi
  if test "${FAKE_PLUGIN_FAILURE:-0}" = 1; then
    printf '%s\n' 'ERROR' 'fixture plugin update failed' \
      >"$ONESIMUS_UPDATE_REPORT"
    exit 32
  fi
  printf '%s\n' 'OK' '7 fixture plugins synchronized' \
    >"$ONESIMUS_UPDATE_REPORT"
  exit 0
fi

if test -n "${FAKE_VIM_LIFECYCLE_LOG:-}"; then
  printf '%s\n' "launch $*" >>"$FAKE_VIM_LIFECYCLE_LOG"
fi
EOF

# A fixed clock exercises backup collision handling deterministically.
cat >"$fake_bin/date" <<'EOF'
#!/bin/sh
echo '20260714-120000'
EOF

# Fail deterministically if an existing checkout reaches its network fetch
# before install.sh has handed execution to its private staged copy.  Pull is
# forbidden: the watchdog must only cover fetch, never a working-tree update.
cat >"$fake_bin/staged-git" <<'EOF'
#!/bin/sh
case " $* " in
  *' pull '*)
    echo 'the updater used pull instead of a bounded fetch' >&2
    exit 96
    ;;
  *' fetch '*)
    test -n "${ONESIMUS_INSTALLER_STAGED:-}" || {
      echo 'fetch reached the unstaged installer' >&2
      exit 97
    }
    ;;
esac
exec "$REAL_GIT" "$@"
EOF
chmod +x "$fake_bin/vim" "$fake_bin/date" "$fake_bin/staged-git"

# ---------------------------------------------------------------------------
# Fresh installation: stage before mutation, preserve private configuration,
# and produce a loader that survives spaces and a literal quote in its path.

printf '%s\n' 'set ruler' 'let g:private_setting = 42' >"$home/.vimrc"
cp "$home/.vimrc" "$work/original-vimrc"
printf '%s\n' 'leave this file alone' >"$root/.vimrc"
cp "$root/.vimrc" "$work/root-vimrc"

FAKE_VIM_LOG=$plugin_log \
  run_installer "$home" "$installer" "$log" \
    --root "$root" --no-launch

target=$root/vimrc
test -d "$target/.git" || fail 'repository was not cloned'
test -x "$target/install.sh" || fail 'installed updater is not executable'
test -r "$target/scripts/update_plugins.vim" \
  || fail 'plugin update helper was not installed'
assert_same "$work/root-vimrc" "$root/.vimrc"
assert_same "$work/original-vimrc" \
  "$home/.vimrc.onesimus-backup.20260714-120000"
assert_contains "$home/.vimrc" 'BEGIN ONESIMUS MANAGED CONFIGURATION'
canonical_target=$(CDPATH= cd -- "$target" && pwd -P)
escaped_target=$(printf '%s' "$canonical_target" | sed "s/'/''/g")
assert_contains "$home/.vimrc" "let \$VIMRCDIR = '$escaped_target'"
assert_absent "$target/vimrc.backup"
target=$canonical_target
cp "$home/.vimrc" "$work/managed-vimrc"

# Two fresh installers cannot both pass an existence check and let mv nest the
# second repository inside the first.  The install-root claim is acquired
# before clone and remains held until the checkout lock is atomically published.
cat >"$fake_bin/slow-clone-git" <<'EOF'
#!/bin/sh
case " $* " in
  *' clone '*)
    printf '%s\n' ready >"$CLAIM_READY_FILE"
    while test ! -e "$CLAIM_RELEASE_FILE"; do
      sleep 0.05
    done
    ;;
esac
exec "$REAL_GIT" "$@"
EOF
chmod +x "$fake_bin/slow-clone-git"
concurrent_root="$work/concurrent fresh root"
concurrent_home_one="$work/concurrent fresh home one"
concurrent_home_two="$work/concurrent fresh home two"
claim_ready="$work/concurrent claim ready"
claim_release="$work/concurrent claim release"
mkdir -p "$concurrent_root" "$concurrent_home_one" "$concurrent_home_two"
printf '%s\n' 'let g:second_private_vimrc = 1' >"$concurrent_home_two/.vimrc"
cp "$concurrent_home_two/.vimrc" "$work/concurrent-second-vimrc"
TEST_GIT_BIN=$fake_bin/slow-clone-git \
CLAIM_READY_FILE=$claim_ready CLAIM_RELEASE_FILE=$claim_release \
FAKE_VIM_LOG=$plugin_log \
  run_installer "$concurrent_home_one" "$installer" \
    "$work/concurrent-first.log" --root "$concurrent_root" --no-launch &
concurrent_first=$!
claim_checks=0
while test ! -s "$claim_ready" && test "$claim_checks" -lt 100; do
  sleep 0.05
  claim_checks=$((claim_checks + 1))
done
if test ! -s "$claim_ready"; then
  : >"$claim_release"
  wait "$concurrent_first" 2>/dev/null || true
  fail 'the first concurrent installer never reached clone'
fi
concurrent_second_status=0
TEST_GIT_BIN=$real_git FAKE_VIM_LOG=$plugin_log \
  run_installer "$concurrent_home_two" "$installer" \
    "$work/concurrent-second.log" --root "$concurrent_root" --no-launch \
  || concurrent_second_status=$?
: >"$claim_release"
concurrent_first_status=0
wait "$concurrent_first" || concurrent_first_status=$?
test "$concurrent_first_status" -eq 0 \
  || fail 'the claim-owning fresh installer did not finish successfully'
test "$concurrent_second_status" -ne 0 \
  || fail 'a second concurrent fresh installer unexpectedly succeeded'
assert_contains "$work/concurrent-second.log" \
  'another Onesimus installation owns'
assert_same "$work/concurrent-second-vimrc" "$concurrent_home_two/.vimrc"
assert_absent "$concurrent_root/vimrc/repository"
assert_no_staging "$concurrent_root"
unset TEST_GIT_BIN CLAIM_READY_FILE CLAIM_RELEASE_FILE

# A normal fresh install completes plugin synchronization in a headless Vim,
# then opens a second process.  The separation is observable and prevents the
# first interactive session from missing plugin scripts discovered at startup.
launch_home="$work/launched fresh home"
launch_root="$work/launched fresh root"
launch_plugin_log="$work/launched plugin invocations.log"
launch_lifecycle_log="$work/launched Vim lifecycle.log"
mkdir -p "$launch_home" "$launch_root"
: >"$launch_plugin_log"
: >"$launch_lifecycle_log"
FAKE_VIM_LOG=$launch_plugin_log \
FAKE_VIM_LIFECYCLE_LOG=$launch_lifecycle_log \
  run_installer "$launch_home" "$installer" "$work/launched-fresh.log" \
    --root "$launch_root"
launch_target=$(CDPATH= cd -- "$launch_root/vimrc" && pwd -P)
test "$(wc -l <"$launch_plugin_log" | tr -d ' ')" = 1 \
  || fail 'a fresh install did not synchronize plugins exactly once'
test "$(sed -n '1s/ .*//p' "$launch_lifecycle_log")" = sync \
  || fail 'a fresh install did not synchronize before opening Vim'
test "$(sed -n '2s/ .*//p' "$launch_lifecycle_log")" = launch \
  || fail 'a fresh install did not open a clean second Vim process'
test "$(wc -l <"$launch_lifecycle_log" | tr -d ' ')" = 2 \
  || fail 'a fresh install used an unexpected Vim lifecycle'
assert_contains "$launch_plugin_log" "-Nu $launch_target/init.vim"
assert_contains "$launch_lifecycle_log" "launch -Nu $launch_home/.vimrc"
if grep -F 'PlugInstall' "$launch_lifecycle_log" >/dev/null; then
  fail 'the interactive first session still owns plugin installation'
fi
assert_contains "$work/launched-fresh.log" '7 fixture plugins synchronized'
assert_contains "$work/launched-fresh.log" 'Opening Vim…'
assert_no_staging "$launch_root"
unset FAKE_VIM_LIFECYCLE_LOG
unset FAKE_VIM_LIFECYCLE_LOG

# Re-running against an existing checkout may reconcile plugins, but the
# byte-exact managed loader is idempotent and creates no extra backup.
: >"$plugin_log"
FAKE_VIM_LOG=$plugin_log \
  run_installer "$home" "$installer" "$work/reinstall.log" \
    --root "$root" --no-launch
assert_same "$work/managed-vimrc" "$home/.vimrc"
assert_absent "$home/.vimrc.onesimus-backup.20260714-120000.1"
test "$(wc -l <"$plugin_log" | tr -d ' ')" = 1 \
  || fail 're-running an existing installation did not synchronize once'

# Supplying --root when re-running the installed copy is still an update.  The
# git wrapper observes the environment at fetch time, which makes the safety
# property testable instead of relying on whether this shell happened to read
# ahead before Git replaced install.sh.
: >"$plugin_log"
wrong_environment_root="$work/stale environment root"
mkdir -p "$wrong_environment_root"
FAKE_VIM_LOG=$plugin_log TEST_GIT_BIN="$fake_bin/staged-git" \
ONESIMUS_INSTALL_ROOT=$wrong_environment_root \
  run_installer "$home" "$target/install.sh" \
    "$work/explicit-root-update.log" --root "$root" --no-launch
test "$(wc -l <"$plugin_log" | tr -d ' ')" = 1 \
  || fail 'an installed --root update did not synchronize exactly once'
assert_same "$work/managed-vimrc" "$home/.vimrc"
assert_no_staging "$root"
unset ONESIMUS_INSTALL_ROOT TEST_GIT_BIN

# Internal handoff variables are never trusted merely because they exist in a
# user's shell.  In particular, cleanup must not unlink an arbitrary path.
untrusted_staged="$work/user-owned staged-looking file"
printf '%s\n' 'do not remove me' >"$untrusted_staged"
cp "$untrusted_staged" "$work/untrusted-staged-copy"
if ONESIMUS_INSTALLER_STAGED=$untrusted_staged \
    ONESIMUS_INSTALL_TARGET_HINT=$target \
    FAKE_VIM_LOG=$plugin_log \
    run_installer "$home" "$target/install.sh" \
      "$work/untrusted-staged.log" --update --core-only; then
  fail 'an untrusted staged-updater path was accepted'
fi
assert_contains "$work/untrusted-staged.log" 'invalid staged updater handoff'
assert_same "$work/untrusted-staged-copy" "$untrusted_staged"
unset ONESIMUS_INSTALLER_STAGED ONESIMUS_INSTALL_TARGET_HINT
assert_no_staging "$root"

# A checkout-wide lock spans fetch, handoff, plugin synchronization, and shim
# migration.  A second updater refuses cleanly and never guesses that a lock is
# stale on the user's behalf.
target_git_dir=$("$real_git" -C "$target" rev-parse --absolute-git-dir)
busy_lock="$target_git_dir/onesimus-update.lock"
mkdir "$busy_lock"
printf '%s\n' '424242' >"$busy_lock/pid"
plugin_calls_before=$(wc -l <"$plugin_log" | tr -d ' ')
if FAKE_VIM_LOG=$plugin_log \
    run_installer "$home" "$target/install.sh" \
      "$work/update-lock.log" --update; then
  fail 'a concurrent update lock was ignored'
fi
assert_contains "$work/update-lock.log" 'another Onesimus update owns'
test "$(wc -l <"$plugin_log" | tr -d ' ')" = "$plugin_calls_before" \
  || fail 'the locked update invoked plugin synchronization'
rm -f "$busy_lock/pid"
rmdir "$busy_lock"
assert_no_staging "$root"

# A generated shim from an older installer is migrated, while a colliding
# backup name is reserved without overwriting either file.
printf '%s\n' 'pre-existing backup' \
  >"$home/.vimrc.onesimus-backup.20260714-120000.1"
printf '%s\n' '" stale managed-loader detail' >>"$home/.vimrc"
cp "$home/.vimrc" "$work/stale-managed-vimrc"
FAKE_VIM_LOG=$plugin_log \
  run_installer "$home" "$installer" "$work/managed-migration.log" \
    --root "$root" --update --core-only
assert_same "$work/stale-managed-vimrc" \
  "$home/.vimrc.onesimus-backup.20260714-120000.2"
test "$(sed -n '1p' "$home/.vimrc.onesimus-backup.20260714-120000.1")" = \
  'pre-existing backup' || fail 'a colliding backup was overwritten'
assert_same "$work/managed-vimrc" "$home/.vimrc"

# Updates never take ownership of a dotfile the installer did not generate.
printf '%s\n' 'second private vimrc' >"$home/.vimrc"
cp "$home/.vimrc" "$work/second-private-vimrc"
: >"$plugin_log"
FAKE_VIM_LOG=$plugin_log \
  run_installer "$home" "$installer" "$work/replacement.log" \
    --root "$root" --no-launch
assert_same "$work/second-private-vimrc" "$home/.vimrc"
assert_contains "$work/replacement.log" 'is user-managed; leaving it unchanged'
test "$(wc -l <"$plugin_log" | tr -d ' ')" = 1 \
  || fail 'updating beside a user-managed vimrc did not synchronize once'
assert_contains "$plugin_log" "-Nu $target/init.vim"
assert_same "$work/stale-managed-vimrc" \
  "$home/.vimrc.onesimus-backup.20260714-120000.2"
cp "$work/managed-vimrc" "$home/.vimrc"

result="$work/loader-result"
HOME=$home ONESIMUS_TEST_RESULT=$result \
  "$real_vim" -Nu "$home/.vimrc" -i NONE -n -es \
  -c 'call writefile([string(get(g:, "onesimus_install_fixture", 0))], $ONESIMUS_TEST_RESULT)' \
  -c 'qa!'
test "$(sed -n '1p' "$result")" = 1 \
  || fail 'generated loader did not source init.vim'
assert_no_staging "$root"

# ---------------------------------------------------------------------------
# The installed updater infers a non-default checkout from its own location.
# An untracked file and a local/fork origin are user-owned and remain intact.
# The upstream installer is deliberately changed to prove that the old staged
# copy pulls core, then hands the resumed phase to the new installed copy.

printf '%s\n' 'keep my local notes' >"$target/local-notes.txt"
origin_before=$($real_git -C "$target" remote get-url origin)
self_update_sentinel="$work/new-installer-resumed"
new_installer="$work/install.self-update.sh"
awk '
  NR == 2 {
    print "if [[ -n ${ONESIMUS_SELF_UPDATE_SENTINEL:-} && ${1:-} = --resume ]]; then"
    print "  printf '\''resumed-new-installer\\n'\'' >\"$ONESIMUS_SELF_UPDATE_SENTINEL\""
    print "fi"
  }
  { print }
' "$upstream/install.sh" >"$new_installer"
mv "$new_installer" "$upstream/install.sh"
chmod +x "$upstream/install.sh"
printf '%s\n' 'updated through installed copy' >"$upstream/release-fixture"
"$real_git" -C "$upstream" add install.sh release-fixture
"$real_git" -C "$upstream" commit -qm 'Exercise updater handoff'

: >"$plugin_log"
FAKE_VIM_LOG=$plugin_log \
ONESIMUS_SELF_UPDATE_SENTINEL=$self_update_sentinel \
  run_installer "$home" "$target/install.sh" "$work/inferred-update.log"

test "$(sed -n '1p' "$target/release-fixture")" = \
  'updated through installed copy' || fail 'custom-root update was not inferred'
test "$(sed -n '1p' "$self_update_sentinel")" = resumed-new-installer \
  || fail 'the post-pull phase did not use the new installer'
test "$(sed -n '1p' "$target/local-notes.txt")" = 'keep my local notes' \
  || fail 'an allowed untracked file was removed'
test "$($real_git -C "$target" remote get-url origin)" = "$origin_before" \
  || fail 'a local/fork origin was rewritten'
test "$(wc -l <"$plugin_log" | tr -d ' ')" = 1 \
  || fail 'plugin synchronization was not invoked exactly once'
assert_contains "$plugin_log" "-S $target/scripts/update_plugins.vim"
assert_contains "$work/inferred-update.log" '7 fixture plugins synchronized'
assert_same "$work/managed-vimrc" "$home/.vimrc"
assert_no_staging "$root"

# A checkout follows its configured upstream rather than assuming that the
# remote is named origin.  Renaming a remote is normal Git state and must not
# turn the updater into a special-case migration.
named_remote_root="$work/named remote root"
named_remote_home="$work/named remote home"
named_remote_target=$named_remote_root/vimrc
mkdir -p "$named_remote_root" "$named_remote_home"
"$real_git" clone -q "$upstream" "$named_remote_target"
"$real_git" -C "$named_remote_target" remote rename origin upstream
named_remote_url=$(
  "$real_git" -C "$named_remote_target" remote get-url upstream
)
publish_file "$upstream" named-remote-fixture \
  'updated through a renamed remote' 'Named upstream remote fixture'

FAKE_VIM_LOG=$plugin_log \
  run_installer "$named_remote_home" "$named_remote_target/install.sh" \
    "$work/named-remote-update.log" --update --core-only
test "$(sed -n '1p' "$named_remote_target/named-remote-fixture")" = \
  'updated through a renamed remote' \
  || fail 'the updater did not follow a renamed upstream remote'
test "$("$real_git" -C "$named_remote_target" remote get-url upstream)" = \
  "$named_remote_url" || fail 'a renamed fork remote was rewritten'
if "$real_git" -C "$named_remote_target" remote get-url origin \
    >/dev/null 2>&1; then
  fail 'the updater recreated an origin remote'
fi
assert_contains "$work/named-remote-update.log" '(remote upstream)'
assert_no_staging "$named_remote_root"

# A core-only update advances the checkout but never starts plugin Vim.
publish_file "$upstream" core-only-fixture 'core only reached here' \
  'Core-only fixture'
plugin_calls_before=$(wc -l <"$plugin_log" | tr -d ' ')
FAKE_VIM_LOG=$plugin_log \
  run_installer "$home" "$target/install.sh" "$work/core-only.log" \
    --update --core-only
test "$(sed -n '1p' "$target/core-only-fixture")" = 'core only reached here' \
  || fail 'core-only update did not update core'
test "$(wc -l <"$plugin_log" | tr -d ' ')" = "$plugin_calls_before" \
  || fail 'core-only update invoked plugin synchronization'
assert_contains "$work/core-only.log" 'Plugins were left unchanged'
assert_no_staging "$root"

# Plugin failure is reported after core and never rolls back or corrupts the
# now-valid loader.  The same installed command can be retried successfully.
publish_file "$upstream" plugin-failure-fixture 'core survives plugin failure' \
  'Plugin failure fixture'
cp "$home/.vimrc" "$work/pre-plugin-failure-vimrc"
if FAKE_VIM_LOG=$plugin_log FAKE_PLUGIN_FAILURE=1 \
    run_installer "$home" "$target/install.sh" "$work/plugin-failure.log" \
      --update; then
  fail 'injected plugin synchronization failure unexpectedly succeeded'
fi
test "$(sed -n '1p' "$target/plugin-failure-fixture")" = \
  'core survives plugin failure' || fail 'core did not survive plugin failure'
assert_same "$work/pre-plugin-failure-vimrc" "$home/.vimrc"
assert_contains "$work/plugin-failure.log" 'fixture plugin update failed'
assert_contains "$work/plugin-failure.log" \
  'the core is ready, but plugin synchronization failed'
assert_no_staging "$root"

FAKE_VIM_LOG=$plugin_log FAKE_PLUGIN_FAILURE=0 \
  run_installer "$home" "$target/install.sh" "$work/plugin-retry.log" \
    --update
assert_contains "$work/plugin-retry.log" '7 fixture plugins synchronized'
assert_same "$work/pre-plugin-failure-vimrc" "$home/.vimrc"
assert_no_staging "$root"

# A wedged plugin subprocess is bounded and leaves the next update retryable.
if FAKE_VIM_LOG=$plugin_log FAKE_PLUGIN_HANG=1 \
    ONESIMUS_PLUGIN_TIMEOUT=1 \
    run_installer "$home" "$target/install.sh" "$work/plugin-timeout.log" \
      --update; then
  fail 'a wedged plugin synchronization unexpectedly succeeded'
fi
assert_contains "$work/plugin-timeout.log" \
  'plugin synchronization timed out after 1s'
assert_no_staging "$root"

# A command that ignores TERM must still be bounded.  This also exercises the
# repository lock cleanup on the fetch-timeout path.
cat >"$fake_bin/stubborn-git" <<'EOF'
#!/bin/sh
case " $* " in
  *' fetch '*)
    trap '' TERM
    (
      trap '' TERM
      while :; do :; done
    ) &
    child=$!
    printf '%s\n' "$child" >"$STUBBORN_CHILD_PID_FILE"
    wait "$child"
    ;;
esac
exec "$REAL_GIT" "$@"
EOF
chmod +x "$fake_bin/stubborn-git"
stubborn_child_file="$work/stubborn child pid"
if TEST_GIT_BIN=$fake_bin/stubborn-git ONESIMUS_GIT_TIMEOUT=1 \
    STUBBORN_CHILD_PID_FILE=$stubborn_child_file \
    FAKE_VIM_LOG=$plugin_log \
    run_installer "$home" "$target/install.sh" \
      "$work/git-timeout.log" --update --core-only; then
  fail 'a fetch that ignored TERM unexpectedly completed'
fi
assert_contains "$work/git-timeout.log" \
  'repository update timed out'
test -s "$stubborn_child_file" \
  || fail 'the stubborn fetch did not publish its child pid'
stubborn_child=$(sed -n '1p' "$stubborn_child_file")
assert_process_stopped "$stubborn_child" \
  'a TERM-ignoring fetch descendant survived the process-group timeout'
assert_no_staging "$root"
unset TEST_GIT_BIN ONESIMUS_GIT_TIMEOUT FAKE_PLUGIN_HANG \
  ONESIMUS_PLUGIN_TIMEOUT STUBBORN_CHILD_PID_FILE

# Interrupting the updater itself follows the same group-wide shutdown rule.
# The checkout lock remains held until a TERM-ignoring fetch child is dead.
cat >"$fake_bin/interrupt-git" <<'EOF'
#!/bin/sh
case " $* " in
  *' fetch '*)
    trap '' TERM
    (
      trap '' TERM
      while :; do :; done
    ) &
    child=$!
    printf '%s\n' "$child" >"$INTERRUPT_CHILD_PID_FILE"
    printf '%s\n' ready >"$INTERRUPT_READY_FILE"
    wait "$child"
    ;;
esac
exec "$REAL_GIT" "$@"
EOF
chmod +x "$fake_bin/interrupt-git"
interrupt_ready="$work/interrupt ready"
interrupt_child_file="$work/interrupt child pid"
TEST_GIT_BIN=$fake_bin/interrupt-git \
INTERRUPT_READY_FILE=$interrupt_ready \
INTERRUPT_CHILD_PID_FILE=$interrupt_child_file \
FAKE_VIM_LOG=$plugin_log \
  run_installer "$home" "$target/install.sh" \
    "$work/interrupted-update.log" --update --core-only &
interrupt_wrapper=$!
interrupt_checks=0
while test ! -s "$interrupt_ready" && test "$interrupt_checks" -lt 100; do
  sleep 0.05
  interrupt_checks=$((interrupt_checks + 1))
done
test -s "$interrupt_ready" || {
  kill "$interrupt_wrapper" 2>/dev/null || true
  fail 'the interrupt fixture never reached fetch'
}
interrupt_owner=$(sed -n '1p' "$target_git_dir/onesimus-update.lock/pid")
kill -TERM "$interrupt_owner"
interrupt_status=0
wait "$interrupt_wrapper" || interrupt_status=$?
test "$interrupt_status" -ne 0 \
  || fail 'an interrupted updater unexpectedly reported success'
interrupt_child=$(sed -n '1p' "$interrupt_child_file")
assert_process_stopped "$interrupt_child" \
  'an updater interrupt released control before its fetch child died'
assert_no_staging "$root"
unset TEST_GIT_BIN INTERRUPT_READY_FILE INTERRUPT_CHILD_PID_FILE

# ---------------------------------------------------------------------------
# custom/plugins.vim was tracked by old releases even though it was explicitly
# intended for personal edits.  The one safe dirty-worktree exception migrates
# an unstaged edit byte-for-byte to the new ignored local-file convention.
# A staged edit is deliberate repository state and must still stop the update.

custom_upstream="$work/legacy custom upstream"
custom_root="$work/legacy plugins root"
custom_home="$work/legacy custom home"
staged_custom_root="$work/staged custom root"
staged_custom_home="$work/staged custom home"
staged_custom_plugin_log="$work/staged-custom-plugin.log"
mkdir -p "$custom_upstream" "$custom_root" "$custom_home" \
  "$staged_custom_root" "$staged_custom_home"
make_fixture_repo "$custom_upstream" '" Project: Onesimus Vim'
mkdir -p "$custom_upstream/custom"
printf '%s\n' '" Legacy user-editable plugin file' \
  '" Plug '\''old/default-plugin'\''' >"$custom_upstream/custom/plugins.vim"
"$real_git" -C "$custom_upstream" add custom/plugins.vim
"$real_git" -C "$custom_upstream" commit -qm 'Track the legacy custom file'

"$real_git" clone -q "$custom_upstream" "$custom_root/vimrc"
"$real_git" clone -q "$custom_upstream" "$staged_custom_root/vimrc"
custom_target=$custom_root/vimrc
staged_custom_target=$staged_custom_root/vimrc
printf '%s\n' '" my plugin choices — preserve these bytes' \
  'Plug '\''private/example'\'', { '\''branch'\'': '\''work tree'\'' }' \
  'let g:custom_fixture = "spaces, $dollars, and '\''quotes"' \
  >"$custom_target/custom/plugins.vim"
cp "$custom_target/custom/plugins.vim" "$work/custom-plugins-user-copy"
printf '%s\n' '" deliberately staged personal plugin change' \
  'Plug '\''private/staged'\''' >"$staged_custom_target/custom/plugins.vim"
"$real_git" -C "$staged_custom_target" add custom/plugins.vim
cp "$staged_custom_target/custom/plugins.vim" "$work/staged-custom-copy"
printf '%s\n' 'private shim must survive refusal' >"$staged_custom_home/.vimrc"
cp "$staged_custom_home/.vimrc" "$work/staged-custom-vimrc"

"$real_git" -C "$custom_upstream" rm -q custom/plugins.vim
printf '%s\n' '/custom/plugins.vim' >"$custom_upstream/.gitignore"
mkdir -p "$custom_upstream/custom"
printf '%s\n' \
  '" Copy this file to custom/plugins.vim; the local file is ignored.' \
  '" Plug '\''wakatime/vim-wakatime'\''' \
  >"$custom_upstream/custom/plugins.vim.example"
"$real_git" -C "$custom_upstream" add .gitignore custom/plugins.vim.example
"$real_git" -C "$custom_upstream" commit -qm \
  'Make personal plugin declarations update-safe'

TEST_REPOSITORY=$custom_upstream FAKE_VIM_LOG=$plugin_log \
  run_installer "$custom_home" "$custom_target/install.sh" \
    "$work/custom-migration.log" --update --core-only
assert_same "$work/custom-plugins-user-copy" \
  "$custom_target/custom/plugins.vim"
if "$real_git" -C "$custom_target" ls-files --error-unmatch \
    custom/plugins.vim >/dev/null 2>&1; then
  fail 'migrated custom/plugins.vim is still tracked'
fi
"$real_git" -C "$custom_target" check-ignore -q custom/plugins.vim \
  || fail 'migrated custom/plugins.vim is not ignored'
"$real_git" -C "$custom_target" ls-files --error-unmatch \
  custom/plugins.vim.example >/dev/null 2>&1 \
  || fail 'the custom plugin example was not installed as a tracked file'
test -z "$("$real_git" -C "$custom_target" status --porcelain)" \
  || fail 'custom plugin migration left the checkout dirty'
assert_contains "$work/custom-migration.log" \
  'Preserving your custom/plugins.vim during this update.'
assert_contains "$work/custom-migration.log" \
  'Restored your custom/plugins.vim as an update-safe local file.'
test -z "$(find "$custom_target/custom" \
  -name '.plugins.vim.onesimus-*' -print)" \
  || fail 'custom plugin migration left a preservation file behind'
assert_no_staging "$custom_root"

if TEST_REPOSITORY=$custom_upstream FAKE_VIM_LOG=$staged_custom_plugin_log \
    run_installer "$staged_custom_home" "$staged_custom_target/install.sh" \
      "$work/staged-custom-update.log" --update --core-only; then
  fail 'a staged custom/plugins.vim change unexpectedly updated'
fi
assert_contains "$work/staged-custom-update.log" \
  'the checkout has tracked changes; commit or stash them before updating'
assert_same "$work/staged-custom-copy" \
  "$staged_custom_target/custom/plugins.vim"
assert_same "$work/staged-custom-vimrc" "$staged_custom_home/.vimrc"
assert_absent "$staged_custom_target/custom/plugins.vim.example"
assert_absent "$staged_custom_plugin_log"
assert_no_staging "$staged_custom_root"

# ---------------------------------------------------------------------------
# Legacy Onesimos checkouts remain valid update sources.  Replacing their old
# loader creates the normal HOME backup; the historical repository-local
# vimrc.backup is untracked user data and must not be moved or deleted.

legacy_upstream="$work/legacy local fork"
legacy_root="$work/legacy custom root"
legacy_home="$work/legacy home"
mkdir -p "$legacy_upstream" "$legacy_root" "$legacy_home"
make_fixture_repo "$legacy_upstream" '" Project: Onesimos Vim'
write_legacy_installer "$legacy_upstream/install.sh"
"$real_git" -C "$legacy_upstream" add install.sh
"$real_git" -C "$legacy_upstream" commit -qm \
  'Represent the pre-handoff Onesimos installer'
"$real_git" clone -q "$legacy_upstream" "$legacy_root/vimrc"
legacy_target=$legacy_root/vimrc
printf '%s\n' 'historical repository backup' >"$legacy_target/vimrc.backup"
cp "$legacy_target/vimrc.backup" "$work/legacy-repo-backup"
printf '%s\n' \
  '"return" 2>&- || "exit"' \
  '' \
  "let \$VIMRCDIR = '$legacy_target'" \
  "let \$MYVIMDOT = \$VIMRCDIR.'/init.vim'" \
  '' \
  'if filereadable(glob($MYVIMDOT))' \
  '    source $MYVIMDOT' \
  'else' \
  "    echomsg 'Vim configuration folder not found!'" \
  'endif' >"$legacy_home/.vimrc"
cp "$legacy_home/.vimrc" "$work/legacy-loader"
legacy_origin=$($real_git -C "$legacy_target" remote get-url origin)

# The fork publishes the current handoff protocol before the user bootstraps
# it with the downloaded current installer.
cp "$installer" "$legacy_upstream/install.sh"
chmod +x "$legacy_upstream/install.sh"
printf '%s\n' '" Project: Onesimus Vim' \
  'let g:onesimus_install_fixture = 1' >"$legacy_upstream/init.vim"
"$real_git" -C "$legacy_upstream" add init.vim install.sh
"$real_git" -C "$legacy_upstream" commit -qm \
  'Publish the safe Onesimus handoff'

TEST_REPOSITORY=$legacy_upstream FAKE_VIM_LOG=$plugin_log \
  run_installer "$legacy_home" "$installer" \
    "$work/legacy-update.log" --root "$legacy_root" --update --core-only
assert_contains "$legacy_home/.vimrc" 'BEGIN ONESIMUS MANAGED CONFIGURATION'
assert_same "$work/legacy-loader" \
  "$legacy_home/.vimrc.onesimus-backup.20260714-120000"
assert_same "$work/legacy-repo-backup" "$legacy_target/vimrc.backup"
test "$($real_git -C "$legacy_target" remote get-url origin)" = "$legacy_origin" \
  || fail 'legacy local/fork origin was rewritten'
assert_no_staging "$legacy_root"

# A stale legacy fork may fast-forward to nothing.  Refuse its old interactive
# installer before it can move or append to the user's vimrc.
stale_upstream="$work/stale legacy fork"
stale_root="$work/stale legacy root"
stale_home="$work/stale legacy home"
stale_executed="$work/stale legacy executed"
mkdir -p "$stale_upstream" "$stale_root" "$stale_home"
make_fixture_repo "$stale_upstream" '" Project: Onesimos Vim'
write_legacy_installer "$stale_upstream/install.sh"
"$real_git" -C "$stale_upstream" add install.sh
"$real_git" -C "$stale_upstream" commit -qm \
  'Keep a stale pre-handoff installer'
"$real_git" clone -q "$stale_upstream" "$stale_root/vimrc"
printf '%s\n' 'let g:private_legacy_vimrc = 1' >"$stale_home/.vimrc"
cp "$stale_home/.vimrc" "$work/stale-legacy-vimrc"

if ONESIMUS_LEGACY_EXECUTED=$stale_executed \
    TEST_REPOSITORY=$stale_upstream FAKE_VIM_LOG=$plugin_log \
    run_installer "$stale_home" "$installer" \
      "$work/stale-legacy-update.log" \
      --root "$stale_root" --update --core-only; then
  fail 'a stale legacy installer unexpectedly accepted the handoff'
fi
assert_contains "$work/stale-legacy-update.log" \
  'installer is too old for safe handoff'
assert_absent "$stale_executed"
assert_same "$work/stale-legacy-vimrc" "$stale_home/.vimrc"
assert_no_staging "$stale_root"

# HANDOFF_V1 alone is no longer enough for a current updater.  Releasing the
# checkout lock before executing such a target would recreate the in-place
# self-update race the private installer is designed to prevent.
v1_upstream="$work/v1-only handoff fork"
v1_root="$work/v1-only handoff root"
v1_home="$work/v1-only handoff home"
mkdir -p "$v1_upstream" "$v1_root" "$v1_home"
make_fixture_repo "$v1_upstream" '" Project: Onesimus Vim'
sed '/^readonly ONESIMUS_INSTALLER_LOCK_V1=1$/d' \
  "$v1_upstream/install.sh" >"$work/v1-only-installer"
mv "$work/v1-only-installer" "$v1_upstream/install.sh"
chmod +x "$v1_upstream/install.sh"
"$real_git" -C "$v1_upstream" add install.sh
"$real_git" -C "$v1_upstream" commit -qm 'Keep only the original handoff protocol'
"$real_git" clone -q "$v1_upstream" "$v1_root/vimrc"
printf '%s\n' 'let g:private_v1_vimrc = 1' >"$v1_home/.vimrc"
cp "$v1_home/.vimrc" "$work/v1-only-vimrc"
if TEST_REPOSITORY=$v1_upstream FAKE_VIM_LOG=$plugin_log \
    run_installer "$v1_home" "$installer" "$work/v1-only-update.log" \
      --root "$v1_root" --update --core-only; then
  fail 'a V1-only target unexpectedly accepted an unlocked handoff'
fi
assert_contains "$work/v1-only-update.log" \
  'installer does not support a locked handoff'
assert_same "$work/v1-only-vimrc" "$v1_home/.vimrc"
assert_no_staging "$v1_root"

# ---------------------------------------------------------------------------
# A fresh, explicitly requested installation preserves the identity of a
# symlinked dotfile in its backup.  Later updates never replace a user-managed
# symlink merely to normalize the loader.

symlink_home="$work/symlink home"
symlink_root="$work/symlink root"
symlink_private="$work/private vimrc target"
mkdir -p "$symlink_home" "$symlink_root"
printf '%s\n' 'set cursorline' >"$symlink_private"
ln -s "$symlink_private" "$symlink_home/.vimrc"
TEST_REPOSITORY=$upstream FAKE_VIM_LOG=$plugin_log \
  run_installer "$symlink_home" "$installer" "$work/symlink-install.log" \
    --root "$symlink_root" --no-launch
test -L "$symlink_home/.vimrc.onesimus-backup.20260714-120000" \
  || fail 'a symlinked vimrc backup lost its identity'
test "$(readlink "$symlink_home/.vimrc.onesimus-backup.20260714-120000")" = \
  "$symlink_private" || fail 'the vimrc backup points somewhere else'

rm -f "$symlink_home/.vimrc"
ln -s "$symlink_private" "$symlink_home/.vimrc"
TEST_REPOSITORY=$upstream FAKE_VIM_LOG=$plugin_log \
  run_installer "$symlink_home" "$symlink_root/vimrc/install.sh" \
    "$work/symlink-update.log" --update --core-only
test -L "$symlink_home/.vimrc" \
  || fail 'an update replaced a user-managed vimrc symlink'
assert_contains "$work/symlink-update.log" 'is user-managed; leaving it unchanged'
test "$(sed -n '1p' "$symlink_private")" = 'set cursorline' \
  || fail 'the symlink target was changed'

# ---------------------------------------------------------------------------
# A tracked-dirty checkout is rejected before pull, shim installation, or Vim.

dirty_upstream="$work/dirty upstream"
dirty_root="$work/dirty root"
dirty_home="$work/dirty home"
dirty_plugin_log="$work/dirty-plugin.log"
mkdir -p "$dirty_upstream" "$dirty_root" "$dirty_home"
make_fixture_repo "$dirty_upstream" '" Project: Onesimus Vim'
"$real_git" clone -q "$dirty_upstream" "$dirty_root/vimrc"
dirty_target=$dirty_root/vimrc
printf '%s\n' '" local tracked edit' >>"$dirty_target/init.vim"
publish_file "$dirty_upstream" should-not-pull 'upstream is newer' \
  'Dirty refusal fixture'
printf '%s\n' 'private vimrc before refusal' >"$dirty_home/.vimrc"
cp "$dirty_home/.vimrc" "$work/dirty-vimrc"

if TEST_REPOSITORY=$dirty_upstream FAKE_VIM_LOG=$dirty_plugin_log \
    run_installer "$dirty_home" "$dirty_target/install.sh" \
      "$work/dirty-update.log" --update; then
  fail 'tracked-dirty checkout unexpectedly updated'
fi
assert_contains "$work/dirty-update.log" \
  'the checkout has tracked changes; commit or stash them before updating'
assert_absent "$dirty_target/should-not-pull"
assert_same "$work/dirty-vimrc" "$dirty_home/.vimrc"
assert_absent "$dirty_plugin_log"
assert_no_staging "$dirty_root"

# ---------------------------------------------------------------------------
# Failures before a checkout exists are byte-preserving and never leave stage.

cat >"$fake_bin/failing-git" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FAIL_GIT_LOG"
exit 73
EOF
chmod +x "$fake_bin/failing-git"
failure_home="$work/failure home"
failure_root="$work/failure root"
mkdir -p "$failure_home" "$failure_root"
printf 'private\000vimrc\n' >"$failure_home/.vimrc"
cp "$failure_home/.vimrc" "$work/failure-vimrc"

if TEST_GIT_BIN=$fake_bin/failing-git \
    TEST_REPOSITORY=https://invalid.example/never-contact-network.git \
    FAIL_GIT_LOG=$work/failing-git.log FAKE_VIM_LOG=$plugin_log \
    run_installer "$failure_home" "$installer" "$work/failure.log" \
      --root "$failure_root" --no-launch; then
  fail 'clone failure unexpectedly succeeded'
fi
assert_same "$work/failure-vimrc" "$failure_home/.vimrc"
assert_absent "$failure_root/vimrc"
assert_absent "$failure_home/.vimrc.onesimus-backup.20260714-120000"
assert_contains "$work/failing-git.log" clone
assert_no_staging "$failure_root"

# An arbitrary Git checkout at the target path is never pulled as Onesimus.
unrelated_home="$work/unrelated home"
unrelated_root="$work/unrelated root"
mkdir -p "$unrelated_home" "$unrelated_root/vimrc"
printf '%s\n' 'unrelated private vimrc' >"$unrelated_home/.vimrc"
cp "$unrelated_home/.vimrc" "$work/unrelated-vimrc"
printf '%s\n' 'set compatible' >"$unrelated_root/vimrc/init.vim"
cp "$installer" "$unrelated_root/vimrc/install.sh"
"$real_git" -C "$unrelated_root/vimrc" init -q
if TEST_GIT_BIN=$real_git TEST_REPOSITORY=$upstream \
    FAKE_VIM_LOG=$plugin_log \
    run_installer "$unrelated_home" "$installer" "$work/unrelated.log" \
      --root "$unrelated_root" --no-launch; then
  fail 'an unrelated Git checkout was accepted as Onesimus'
fi
assert_same "$work/unrelated-vimrc" "$unrelated_home/.vimrc"
assert_contains "$work/unrelated.log" \
  'does not look like an Onesimus checkout'

# Unsupported Vim fails before a directory, checkout, or loader is changed.
old_vim_home="$work/old vim home"
old_vim_root="$work/old vim root"
mkdir -p "$old_vim_home"
printf '%s\n' 'old-vim private config' >"$old_vim_home/.vimrc"
cp "$old_vim_home/.vimrc" "$work/old-vim-vimrc"
if FAKE_VIM_CAPABILITY_FAILURE=1 FAKE_VIM_LOG=$plugin_log \
    run_installer "$old_vim_home" "$installer" "$work/old-vim.log" \
      --root "$old_vim_root" --no-launch; then
  fail 'unsupported Vim unexpectedly succeeded'
fi
assert_same "$work/old-vim-vimrc" "$old_vim_home/.vimrc"
assert_absent "$old_vim_root"
assert_contains "$work/old-vim.log" \
  'Vim 8.2 or newer with +job, +channel, and +timers is required'

assert_contains "$installer" 'https://github.com/BaksiLi/Onesimus.git'

echo 'PASS: installer handles fresh installs, safe updates, and retryable plugin sync'
