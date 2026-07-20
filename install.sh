#!/usr/bin/env bash

set -euo pipefail

readonly ONESIMUS_REPOSITORY_DEFAULT='https://github.com/BaksiLi/Onesimus.git'
# Staged older updaters detect this exact line without executing the new file.
# Keep it while --resume remains backward-compatible with handoff v1.
readonly ONESIMUS_INSTALLER_HANDOFF_V1=1
# A current updater can transfer an already-held update lock across exec.  The
# separate marker lets it remain compatible with older v1 handoff targets.
readonly ONESIMUS_INSTALLER_LOCK_V1=1

install_root=${ONESIMUS_INSTALL_ROOT:-}
repository=${ONESIMUS_REPOSITORY:-$ONESIMUS_REPOSITORY_DEFAULT}
vim_bin=${ONESIMUS_VIM_BIN:-vim}
git_bin=${ONESIMUS_GIT_BIN:-git}
launch_vim=1
update_mode=0
core_only=0
resume_mode=0
stage_dir=
shim_tmp=
installer_tmp=
plugin_log=
plugin_report=
custom_plugins_tmp=
custom_plugins_base_tmp=
custom_plugins_path=
active_pid=
active_pgid=
watchdog_pid=
timeout_marker=
staged_mode=0
update_lock_dir=
update_lock_owned=0
install_claim_dir=
install_claim_owned=0

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) \
  || {
    printf 'Onesimus: cannot resolve the installer location\n' >&2
    exit 1
  }

fail() {
  printf 'Onesimus: %s\n' "$*" >&2
  exit 1
}

canonical_file() {
  local directory basename

  directory=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd -P) || return 1
  basename=$(basename -- "$1")
  printf '%s/%s\n' "$directory" "$basename"
}

# These variables are an exec protocol, not a public configuration surface.
# Validate the staged path before allowing it to affect target selection or
# cleanup; a stale shell environment must never make us remove an arbitrary
# user file.
if [[ -n ${ONESIMUS_INSTALLER_STAGED:-} ]]; then
  staged_file=$(canonical_file "$ONESIMUS_INSTALLER_STAGED") \
    || fail 'invalid staged updater handoff'
  running_file=$(canonical_file "${BASH_SOURCE[0]}") \
    || fail 'invalid staged updater handoff'
  tmp_root=$(CDPATH= cd -- "${TMPDIR:-/tmp}" && pwd -P) \
    || fail 'invalid staged updater handoff'
  staged_basename=$(basename -- "$staged_file")
  [[ $staged_file = "$running_file" \
      && $(dirname -- "$staged_file") = "$tmp_root" \
      && $staged_basename = onesimus-installer.* \
      && -f $staged_file && ! -L $staged_file && -O $staged_file ]] \
    || fail 'invalid staged updater handoff'
  installer_tmp=$staged_file
  staged_mode=1
fi

usage() {
  cat <<'EOF'
Usage: install.sh [--root DIRECTORY] [--no-launch]
       install.sh --update [--root DIRECTORY] [--core-only]

Install Onesimus in DIRECTORY/vimrc.  The default DIRECTORY is $HOME.

  --root DIRECTORY  choose the parent directory without prompting
  --update          safely update an existing checkout and its plugins
  --core-only       with --update, leave plugin synchronization for later
  --no-launch       on a new install, defer plugin sync and opening Vim
  -h, --help        show this help
EOF
}

release_update_lock() {
  local owner

  (( update_lock_owned )) || return 0
  owner=$(sed -n '1p' "$update_lock_dir/pid" 2>/dev/null || true)
  if [[ $owner = "$$" ]]; then
    rm -f "$update_lock_dir/pid" 2>/dev/null || true
    rmdir "$update_lock_dir" 2>/dev/null || true
  fi
  update_lock_dir=
  update_lock_owned=0
}

release_install_claim() {
  local owner

  (( install_claim_owned )) || return 0
  owner=$(sed -n '1p' "$install_claim_dir/pid" 2>/dev/null || true)
  if [[ $owner = "$$" ]]; then
    rm -f "$install_claim_dir/pid" 2>/dev/null || true
    rmdir "$install_claim_dir" 2>/dev/null || true
  fi
  install_claim_dir=
  install_claim_owned=0
}

acquire_install_claim() {
  local expected holder

  expected=$install_root/.onesimus-install.lock
  if (umask 077; mkdir "$expected") 2>/dev/null; then
    if ! printf '%s\n' "$$" >"$expected/pid"; then
      rm -f "$expected/pid" 2>/dev/null || true
      rmdir "$expected" 2>/dev/null || true
      fail 'could not record ownership of the installation claim'
    fi
    install_claim_dir=$expected
    install_claim_owned=1
    return 0
  fi

  holder=$(sed -n '1p' "$expected/pid" 2>/dev/null || true)
  if [[ $holder =~ ^[1-9][0-9]*$ ]]; then
    fail "another Onesimus installation owns $expected (pid $holder); if that process no longer exists, remove the claim directory and retry"
  fi
  fail "another Onesimus installation owns $expected; if no install is running, remove the claim directory and retry"
}

adopt_transferred_update_lock_early() {
  local expected git_directory owner resume_target supplied

  (( resume_mode )) || return 0
  supplied=${ONESIMUS_UPDATE_LOCK:-}
  [[ -n $supplied ]] || return 0
  [[ -n ${ONESIMUS_INSTALL_RESUME:-} && -d $ONESIMUS_INSTALL_RESUME ]] \
    || fail 'the resumed updater could not verify its update lock'
  resume_target=$(CDPATH= cd -- "$ONESIMUS_INSTALL_RESUME" && pwd -P) \
    || fail 'the resumed updater could not verify its update lock'
  git_directory=$("$git_bin" -C "$resume_target" rev-parse \
    --absolute-git-dir 2>/dev/null) \
    || fail 'the resumed updater could not verify its update lock'
  expected=$git_directory/onesimus-update.lock
  owner=$(sed -n '1p' "$expected/pid" 2>/dev/null || true)
  [[ $supplied = "$expected" && -d $expected && $owner = "$$" ]] \
    || fail 'the resumed updater could not verify its update lock'
  update_lock_dir=$expected
  update_lock_owned=1
}

signal_active_group() {
  local signal=$1

  if [[ -n $active_pgid ]] \
      && kill "-$signal" -- "-$active_pgid" 2>/dev/null; then
    return 0
  fi
  [[ -z $active_pid ]] || kill "-$signal" "$active_pid" 2>/dev/null
}

stop_active_process() {
  [[ -n $active_pid ]] || return 0

  signal_active_group TERM || true
  # Give Git/Vim and their helpers one bounded chance to clean up, then ensure
  # no descendant can keep writing after the checkout lock is released.
  sleep 1
  signal_active_group KILL || true
  wait "$active_pid" 2>/dev/null || true
  active_pid=
  active_pgid=
}

cleanup() {
  # Cleanup is a best-effort sequence with one non-negotiable invariant: a
  # failure removing an incidental temp file must not skip process shutdown or
  # lock release.
  set +e
  if [[ -n $watchdog_pid ]]; then
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    watchdog_pid=
  fi
  stop_active_process
  if [[ -n $timeout_marker && -e $timeout_marker ]]; then
    rm -f "$timeout_marker"
  fi
  if [[ -n $custom_plugins_base_tmp && -e $custom_plugins_base_tmp ]]; then
    rm -f "$custom_plugins_base_tmp"
  fi
  if [[ -n $custom_plugins_tmp && -e $custom_plugins_tmp ]]; then
    if [[ -n $custom_plugins_path ]]; then
      mv -f "$custom_plugins_tmp" "$custom_plugins_path" 2>/dev/null \
        || printf 'Onesimus: could not restore %s from %s\n' \
          "$custom_plugins_path" "$custom_plugins_tmp" >&2
    fi
  fi
  if [[ -n $shim_tmp && -e $shim_tmp ]]; then
    rm -f "$shim_tmp"
  fi
  if [[ -n $installer_tmp && -e $installer_tmp ]]; then
    rm -f "$installer_tmp"
  fi
  if [[ -n $plugin_log && -e $plugin_log ]]; then
    rm -f "$plugin_log"
  fi
  if [[ -n $plugin_report && -e $plugin_report ]]; then
    rm -f "$plugin_report"
  fi
  if [[ -n $stage_dir && -d $stage_dir ]]; then
    rm -rf "$stage_dir"
  fi
  release_install_claim
  release_update_lock
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

run_with_timeout() {
  local seconds=$1
  local status
  shift

  [[ $seconds =~ ^[1-9][0-9]*$ ]] \
    || fail "invalid timeout in seconds: $seconds"
  timeout_marker=$(mktemp "${TMPDIR:-/tmp}/onesimus-timeout.XXXXXX") \
    || fail 'cannot create a timeout marker'
  rm -f "$timeout_marker"

  # Monitor mode gives this background job a dedicated process group even in a
  # non-interactive Bash.  Git, curl/ssh, Vim, and build helpers can therefore
  # be stopped as one operation instead of leaving an orphan behind.
  set -m
  "$@" &
  active_pid=$!
  active_pgid=$active_pid
  set +m
  (
    sleep "$seconds"
    if kill -0 "$active_pid" 2>/dev/null; then
      : >"$timeout_marker"
      signal_active_group TERM || true
      sleep 2
      signal_active_group KILL || true
    fi
  ) &
  watchdog_pid=$!

  status=0
  wait "$active_pid" || status=$?

  if [[ -e $timeout_marker ]]; then
    # The leader may exit on TERM before a helper does.  Let the watchdog finish
    # its group-wide KILL before forgetting the group or releasing any lock.
    wait "$watchdog_pid" 2>/dev/null || true
  else
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
  fi
  watchdog_pid=
  active_pid=
  active_pgid=

  if [[ -e $timeout_marker ]]; then
    rm -f "$timeout_marker"
    timeout_marker=
    return 124
  fi
  timeout_marker=
  return "$status"
}

while (( $# )); do
  case $1 in
    --root)
      (( $# >= 2 )) || fail '--root requires a directory'
      install_root=$2
      shift 2
      ;;
    --root=*)
      install_root=${1#*=}
      shift
      ;;
    --no-launch)
      launch_vim=0
      shift
      ;;
    --update)
      update_mode=1
      shift
      ;;
    --core-only)
      core_only=1
      shift
      ;;
    --resume)
      [[ -n ${ONESIMUS_INSTALL_RESUME:-} ]] \
        || fail '--resume is reserved for the installer'
      resume_mode=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

(( !core_only || update_mode )) || fail '--core-only requires --update'

command -v "$git_bin" >/dev/null 2>&1 || fail 'git is required'
adopt_transferred_update_lock_early
[[ -n ${HOME:-} && -d $HOME ]] || fail 'HOME must name an existing directory'
command -v "$vim_bin" >/dev/null 2>&1 || fail 'Vim is required'

# Ask Vim itself: feature names and v:version are less fragile than parsing the
# human-readable --version output, and catch minimal builds as well as old ones.
if ! "$vim_bin" -Nu NONE -U NONE -i NONE -n -es \
    --cmd 'if v:version < 802 || !has("job") || !has("channel") || !has("timers") | cquit 42 | endif' \
    -c 'qa!' </dev/null >/dev/null 2>&1; then
  vim_version=$({ "$vim_bin" --version 2>/dev/null || true; } | sed -n '1p')
  [[ -n $vim_version ]] || vim_version='unknown Vim build'
  fail "Vim 8.2 or newer with +job, +channel, and +timers is required ($vim_version)"
fi

is_onesimus_checkout() {
  local project_header

  [[ -r $1/init.vim && -r $1/install.sh ]] || return 1
  project_header=$(sed -n '1p' "$1/init.vim")
  case $project_header in
    '" Project: Onesimus Vim'|'" Project: Onesimos Vim') return 0 ;;
    *) return 1 ;;
  esac
}

# Running the installed copy is the most reliable update entrypoint, especially
# for checkouts outside ~/vimrc: its own directory is unambiguous and needs no
# remembered --root argument.
if (( !update_mode && !resume_mode )) && [[ -z $install_root ]] \
    && is_onesimus_checkout "$script_dir" \
    && "$git_bin" -C "$script_dir" rev-parse --is-inside-work-tree \
      >/dev/null 2>&1; then
  update_mode=1
fi

if (( !update_mode && !resume_mode )); then
  cat <<'EOF'
         .-://:-.      `:`
      .+syyyyyyyys+.  :ooo/`
     /yyyyyyyyyyyyyy+``/oooo/`
    +yys+++++oooooooy+  /ooooo/````````````..
   `yyy/...``````...sy. .ooooo/...```````..`
   `yyyyss+``````sssyy. .oooooo++:`````..`
    +yyyyy+``````syyy+  :ooooo+:.````..`
    `+yyyy+``````syy+` -oooo+:.````.:+/.
      .+sy+``````o+. `:ooo+:.````.:+ooo+/.
   `::.``.:``````-`./+oo+:.````.:+ooooooo+/.
  -+ooo+/::``````++ooo+:.````.:+ooooooooooo+/.
  `-+ooooo/``````+oo+:.````.:+oooooooooooooo+/`
    `-+ooo/``````++:.````.:+oooooooooooooo+:.
      `-+o/``````-.````.:+oooooooooooooo+:`
        `-:``````````.:+oooooooooooooo+-`
          -````````.:+oooooooooooooo/-`
          -``````.:+oooooooooooooo/.
          -````.:+ooooooooooooo+:`
          -``..``-+oooooooooo+:`
          -..`    `-+oooooo+-`
          -`         -+oo/.
                       -.

Onesimus — a helpful Vim distribution
EOF
fi

expand_home() {
  case $1 in
    '~') printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s/%s\n' "$HOME" "${1:2}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

inferred_target=
if (( resume_mode )); then
  inferred_target=$ONESIMUS_INSTALL_RESUME
elif (( staged_mode )); then
  (( update_mode )) || fail 'invalid staged updater handoff'
  [[ -n ${ONESIMUS_INSTALL_TARGET_HINT:-} ]] \
    || fail 'invalid staged updater handoff'
  inferred_target=$ONESIMUS_INSTALL_TARGET_HINT
elif (( update_mode )) && [[ -z $install_root ]]; then
  if is_onesimus_checkout "$script_dir" \
      && "$git_bin" -C "$script_dir" rev-parse --is-inside-work-tree \
        >/dev/null 2>&1; then
    inferred_target=$script_dir
  else
    install_root=$HOME
  fi
elif [[ -z $install_root ]]; then
  printf '\nInstall the repository at %s/vimrc? [Y/n] ' "$HOME"
  IFS= read -r answer || fail 'installation cancelled'
  case $answer in
    ''|y|Y|yes|YES|Yes)
      install_root=$HOME
      ;;
    n|N|no|NO|No)
      printf 'Parent directory: '
      IFS= read -r install_root || fail 'installation cancelled'
      [[ -n $install_root ]] || fail 'a parent directory is required'
      ;;
    *)
      fail "please answer yes or no"
      ;;
  esac
fi

if [[ -n $inferred_target ]]; then
  [[ -d $inferred_target ]] || fail "$inferred_target is not a directory"
  target=$(CDPATH= cd -- "$inferred_target" && pwd -P) \
    || fail "cannot resolve $inferred_target"
  install_root=$(dirname -- "$target")
else
  install_root=$(expand_home "$install_root")
  [[ $install_root = / ]] || install_root=${install_root%/}
  [[ -n $install_root ]] || fail 'the installation root cannot be empty'
  [[ $install_root != '~'* ]] \
    || fail 'only ~ and ~/… are supported; use an absolute path for another user'

  if [[ ! -d $install_root ]]; then
    (( !update_mode )) \
      || fail "no Onesimus checkout exists below $install_root"
    printf 'Creating %s\n' "$install_root"
    mkdir -p "$install_root" || fail "cannot create $install_root"
  fi
  install_root=$(CDPATH= cd -- "$install_root" && pwd -P) \
    || fail "cannot resolve $install_root"
  target=$install_root/vimrc
fi

if (( update_mode )) && [[ ! -e $target && ! -L $target ]]; then
  fail "no Onesimus checkout found at $target; omit --update for a new installation"
fi

# An explicit --root can still point back to the checkout containing this
# installer.  Recognize every valid existing target before the staging gate;
# otherwise that spelling would pull while the shell was reading install.sh in
# place, defeating the self-update handoff below.
if (( !update_mode && !resume_mode )) && [[ -e $target || -L $target ]] \
    && is_onesimus_checkout "$target" \
    && "$git_bin" -C "$target" rev-parse --is-inside-work-tree \
      >/dev/null 2>&1; then
  update_mode=1
fi

# Updating an installer in place is not safe: shells are allowed to read a
# script incrementally while Git replaces it.  Continue from a private copy,
# then hand the post-pull phase to the newly checked-out installer below.
if (( update_mode && !resume_mode )); then
  if (( staged_mode )); then
    :
  else
    stage_args=(--update)
    (( core_only )) && stage_args+=(--core-only)
    (( launch_vim )) || stage_args+=(--no-launch)
    installer_tmp=$(mktemp "${TMPDIR:-/tmp}/onesimus-installer.XXXXXX") \
      || fail 'cannot stage the updater'
    cp -- "${BASH_SOURCE[0]}" "$installer_tmp" \
      || fail 'cannot stage the updater'
    chmod 700 "$installer_tmp"
    exec env \
      ONESIMUS_INSTALL_ROOT= \
      ONESIMUS_INSTALL_RESUME= \
      ONESIMUS_UPDATE_LOCK= \
      ONESIMUS_INSTALLER_STAGED="$installer_tmp" \
      ONESIMUS_INSTALL_TARGET_HINT="$target" \
      bash "$installer_tmp" "${stage_args[@]}"
  fi
fi

preserve_legacy_custom_plugins() {
  custom_plugins_path=$target/custom/plugins.vim
  [[ -f $custom_plugins_path && ! -L $custom_plugins_path ]] \
    || fail 'custom/plugins.vim changed type; move it aside before updating'

  custom_plugins_tmp=$(mktemp \
    "$target/custom/.plugins.vim.onesimus-user.XXXXXX") \
    || fail 'cannot preserve custom/plugins.vim'
  cp -p "$custom_plugins_path" "$custom_plugins_tmp" \
    || fail 'cannot preserve custom/plugins.vim'

  custom_plugins_base_tmp=$(mktemp \
    "$target/custom/.plugins.vim.onesimus-base.XXXXXX") \
    || fail 'cannot prepare the custom plugin migration'
  "$git_bin" -C "$target" show HEAD:custom/plugins.vim \
    >"$custom_plugins_base_tmp" \
    || fail 'cannot read the original custom/plugins.vim'
  chmod 644 "$custom_plugins_base_tmp"
  mv "$custom_plugins_base_tmp" "$custom_plugins_path" \
    || fail 'cannot prepare custom/plugins.vim for update'
  custom_plugins_base_tmp=
  printf 'Preserving your custom/plugins.vim during this update.\n'
}

restore_legacy_custom_plugins() {
  if [[ -n $custom_plugins_tmp && -e $custom_plugins_tmp ]]; then
    mv -f "$custom_plugins_tmp" "$custom_plugins_path" \
      || fail 'the checkout updated, but custom/plugins.vim could not be restored'
    custom_plugins_tmp=
    printf 'Restored your custom/plugins.vim as an update-safe local file.\n'
  fi
}

expected_update_lock() {
  local git_directory

  git_directory=$("$git_bin" -C "$target" rev-parse --absolute-git-dir \
    2>/dev/null) || fail 'could not locate the checkout metadata'
  printf '%s/onesimus-update.lock\n' "$git_directory"
}

acquire_update_lock() {
  local expected holder

  (( update_lock_owned )) && return 0
  expected=$(expected_update_lock)
  if (umask 077; mkdir "$expected") 2>/dev/null; then
    if ! printf '%s\n' "$$" >"$expected/pid"; then
      rmdir "$expected" 2>/dev/null || true
      fail 'could not record ownership of the update lock'
    fi
    update_lock_dir=$expected
    update_lock_owned=1
    return 0
  fi

  holder=$(sed -n '1p' "$expected/pid" 2>/dev/null || true)
  if [[ $holder =~ ^[1-9][0-9]*$ ]]; then
    fail "another Onesimus update owns $expected (pid $holder); if that process no longer exists, remove the lock directory and retry"
  fi
  fail "another Onesimus update owns $expected; if no update is running, remove the lock directory and retry"
}

adopt_update_lock() {
  local expected owner supplied

  (( update_lock_owned )) && return 0
  supplied=${ONESIMUS_UPDATE_LOCK:-}
  # A v1 staged updater predates lock transfer.  Acquiring here preserves its
  # ability to hand off to a new release, even though its completed fetch could
  # not have been protected retroactively.
  if [[ -z $supplied ]]; then
    acquire_update_lock
    return
  fi

  expected=$(expected_update_lock)
  owner=$(sed -n '1p' "$expected/pid" 2>/dev/null || true)
  [[ $supplied = "$expected" && -d $expected && $owner = "$$" ]] \
    || fail 'the resumed updater could not verify its update lock'
  update_lock_dir=$expected
  update_lock_owned=1
}

prepare_fresh_update_lock() {
  local staged_lock

  staged_lock=$stage_dir/repository/.git/onesimus-update.lock
  (umask 077; mkdir "$staged_lock") 2>/dev/null \
    || fail 'could not prepare the installation lock'
  if ! printf '%s\n' "$$" >"$staged_lock/pid"; then
    rm -f "$staged_lock/pid" 2>/dev/null || true
    rmdir "$staged_lock" 2>/dev/null || true
    fail 'could not record ownership of the installation lock'
  fi

  # The lock moves into existence atomically with the cloned checkout.  Until
  # mv succeeds, the ordinary staging-directory cleanup owns its old path.
  update_lock_dir=$target/.git/onesimus-update.lock
  update_lock_owned=1
}

install_repository() {
  local branch_name clone_status fetch_status merge_status tracked_changes
  local upstream_ref upstream_remote upstream_url

  if [[ -e $target || -L $target ]]; then
    update_mode=1
    [[ -d $target ]] || fail "$target exists and is not a directory"
    "$git_bin" -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      || fail "$target is not a Git working tree"
    is_onesimus_checkout "$target" \
      || fail "$target does not look like an Onesimus checkout"
    acquire_update_lock

    branch_name=$({
      "$git_bin" -C "$target" symbolic-ref --quiet --short HEAD 2>/dev/null \
        || true
    })
    [[ -n $branch_name ]] \
      || fail 'the checkout is detached; choose a branch with an upstream before updating'
    upstream_ref=$({
      "$git_bin" -C "$target" rev-parse \
        --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true
    })
    [[ -n $upstream_ref ]] \
      || fail "branch $branch_name has no configured upstream; update it manually"
    upstream_remote=$({
      "$git_bin" -C "$target" config --get \
        "branch.$branch_name.remote" 2>/dev/null || true
    })
    [[ -n $upstream_remote ]] \
      || fail "cannot identify the remote for upstream $upstream_ref"
    upstream_url=$({
      "$git_bin" -C "$target" remote get-url "$upstream_remote" \
        2>/dev/null || true
    })
    [[ -n $upstream_url ]] \
      || fail "upstream $upstream_ref does not name a fetchable remote"

    if ! tracked_changes=$(
      "$git_bin" -C "$target" status --porcelain --untracked-files=no \
        2>/dev/null
    ); then
      fail 'could not inspect the existing checkout safely'
    fi
    if [[ $tracked_changes == ' M custom/plugins.vim' ]]; then
      preserve_legacy_custom_plugins
    elif [[ -n $tracked_changes ]]; then
      fail 'the checkout has tracked changes; commit or stash them before updating'
    fi

    printf '\nUpdating %s from %s (remote %s)\n' \
      "$target" "$upstream_url" "$upstream_remote"

    # Bound only the network phase.  Once fetch has finished, the local
    # fast-forward runs without a watchdog so a timeout can never interrupt a
    # checkout while Git is replacing files.
    fetch_status=0
    run_with_timeout "${ONESIMUS_GIT_TIMEOUT:-180}" \
      env GIT_TERMINAL_PROMPT=0 \
      "$git_bin" -C "$target" fetch --quiet "$upstream_remote" \
      || fetch_status=$?
    if (( fetch_status == 124 )); then
      fail 'the repository update timed out; check its upstream or network and retry'
    elif (( fetch_status != 0 )); then
      fail 'the repository could not be fetched; check its upstream or network and retry'
    fi

    merge_status=0
    "$git_bin" -C "$target" merge --ff-only --quiet '@{upstream}' \
      || merge_status=$?
    if (( merge_status != 0 )); then
      fail 'the existing checkout could not be fast-forwarded; resolve its branch or upstream manually'
    fi
    restore_legacy_custom_plugins
    is_onesimus_checkout "$target" \
      || fail 'the updated checkout is incomplete or no longer identifies as Onesimus'

    case $upstream_url in
      https://github.com/BaksiLi/Onesimos|\
      https://github.com/BaksiLi/Onesimos.git|\
      git@github.com:BaksiLi/Onesimos|\
      git@github.com:BaksiLi/Onesimos.git)
        "$git_bin" -C "$target" remote set-url "$upstream_remote" \
          "$ONESIMUS_REPOSITORY_DEFAULT" \
          || fail 'the checkout updated, but the official repository URL could not be migrated'
        ;;
    esac
  else
    acquire_install_claim
    [[ ! -e $target && ! -L $target ]] \
      || fail "$target appeared while Onesimus was preparing to clone"
    printf '\nCloning %s\n' "$repository"
    stage_dir=$(mktemp -d "$install_root/.onesimus-install.XXXXXX") \
      || fail "cannot create a staging directory in $install_root"
    clone_status=0
    run_with_timeout "${ONESIMUS_GIT_TIMEOUT:-180}" \
      env GIT_TERMINAL_PROMPT=0 \
      "$git_bin" clone --quiet "$repository" "$stage_dir/repository" \
      || clone_status=$?
    if (( clone_status == 124 )); then
      fail 'clone timed out; your existing Vim configuration was not changed'
    elif (( clone_status != 0 )); then
      fail 'clone failed; your existing Vim configuration was not changed'
    fi
    is_onesimus_checkout "$stage_dir/repository" \
      || fail 'the cloned repository is not an Onesimus checkout'
    prepare_fresh_update_lock
    [[ ! -e $target && ! -L $target ]] \
      || fail "$target appeared while Onesimus was being cloned"
    mv "$stage_dir/repository" "$target"
    rmdir "$stage_dir"
    stage_dir=
    # The checkout's own lock was published inside the same rename.  It now
    # protects handoff, so another fresh installer no longer needs this
    # install-root claim to stay excluded.
    release_install_claim
  fi
}

validate_resumed_checkout() {
  [[ $target = "$ONESIMUS_INSTALL_RESUME" ]] \
    || fail 'the resumed installer target changed unexpectedly'
  [[ -d $target ]] || fail "$target is not a directory"
  "$git_bin" -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "$target is not a Git working tree"
  is_onesimus_checkout "$target" \
    || fail "$target does not look like an Onesimus checkout"
  adopt_update_lock
  [[ $script_dir = "$target" ]] \
    || fail 'the resumed installer is not running from the updated checkout'
}

resume_from_checkout() {
  local lock_handoff
  local -a resume_args

  [[ -r $target/install.sh ]] \
    || fail 'the checked-out installer is missing'
  "$BASH" -n "$target/install.sh" \
    || fail 'the checkout updated, but its installer does not pass a syntax check'
  grep -Fqx 'readonly ONESIMUS_INSTALLER_HANDOFF_V1=1' \
    "$target/install.sh" \
    || fail 'the checkout updated, but its installer is too old for safe handoff; update its upstream to a current Onesimus release'
  grep -Fqx 'readonly ONESIMUS_INSTALLER_LOCK_V1=1' \
    "$target/install.sh" \
    || fail 'the checkout updated, but its installer does not support a locked handoff; update its upstream to a current Onesimus release'
  resume_args=(--resume)
  (( update_mode )) && resume_args+=(--update)
  (( core_only )) && resume_args+=(--core-only)
  (( launch_vim )) || resume_args+=(--no-launch)

  lock_handoff=$update_lock_dir

  if [[ -n $installer_tmp ]]; then
    rm -f "$installer_tmp"
    installer_tmp=
  fi
  exec env \
    ONESIMUS_INSTALL_ROOT= \
    ONESIMUS_INSTALL_RESUME="$target" \
    ONESIMUS_INSTALLER_STAGED= \
    ONESIMUS_INSTALL_TARGET_HINT= \
    ONESIMUS_UPDATE_LOCK="$lock_handoff" \
    bash "$target/install.sh" "${resume_args[@]}"
}

vim_single_quote() {
  # In a Vim single-quoted string, a literal quote is represented by two
  # quotes.  Backslashes are otherwise preserved, which also keeps paths sane.
  printf '%s' "$1" | sed "s/'/''/g"
}

reserve_backup_path() {
  local timestamp backup_base backup suffix

  timestamp=$(date '+%Y%m%d-%H%M%S')
  backup_base=$HOME/.vimrc.onesimus-backup.$timestamp
  backup=$backup_base
  suffix=1
  while ! (umask 077; set -o noclobber; : >"$backup") 2>/dev/null; do
    backup=$backup_base.$suffix
    (( suffix += 1 ))
  done
  printf '%s\n' "$backup"
}

is_legacy_installer_shim() {
  local vimrc=$1
  local line_count

  [[ -f $vimrc && ! -L $vimrc ]] || return 1
  [[ $(sed -n '1p' "$vimrc") == '"return" 2>&- || "exit"' ]] || return 1
  line_count=$(wc -l <"$vimrc" | tr -d ' ')
  (( line_count <= 14 )) || return 1
  grep -F 'let $VIMRCDIR = ' "$vimrc" >/dev/null \
    && grep -F "let \$MYVIMDOT = \$VIMRCDIR.'/init.vim'" "$vimrc" >/dev/null \
    && grep -F 'if filereadable(glob($MYVIMDOT))' "$vimrc" >/dev/null
}

is_managed_installer_shim() {
  [[ -f $1 && ! -L $1 ]] \
    && grep -F 'BEGIN ONESIMUS MANAGED CONFIGURATION' "$1" >/dev/null \
    && grep -F 'END ONESIMUS MANAGED CONFIGURATION' "$1" >/dev/null
}

install_shim() {
  local vimrc=$HOME/.vimrc
  local quoted_target
  local backup
  local -a backup_command

  [[ ! -d $vimrc ]] || fail "$vimrc is a directory"
  quoted_target=$(vim_single_quote "$target")
  shim_tmp=$(mktemp "$HOME/.vimrc.onesimus-tmp.XXXXXX") \
    || fail "cannot create a temporary file in $HOME"
  chmod 600 "$shim_tmp"

  cat >"$shim_tmp" <<EOF
" BEGIN ONESIMUS MANAGED CONFIGURATION
" Generated by install.sh; re-run the installer instead of editing this file.
let \$VIMRCDIR = '$quoted_target'
let \$MYVIMDOT = \$VIMRCDIR . '/init.vim'

if filereadable(\$MYVIMDOT)
  execute 'source ' . fnameescape(\$MYVIMDOT)
else
  echoerr 'Onesimus configuration not found: ' . \$MYVIMDOT
endif
" END ONESIMUS MANAGED CONFIGURATION
EOF

  if [[ -e $vimrc || -L $vimrc ]]; then
    if cmp -s "$shim_tmp" "$vimrc"; then
      rm -f "$shim_tmp"
      shim_tmp=
      printf '%s already points to Onesimus; leaving it unchanged.\n' "$vimrc"
      return
    fi

    # An update already knows which checkout it is updating.  Do not take
    # ownership of an unrelated dotfile or symlink merely to modernize the
    # loader; only shims generated by Onesimus/Onesimos are safe migrations.
    if (( update_mode )) \
        && ! is_managed_installer_shim "$vimrc" \
        && ! is_legacy_installer_shim "$vimrc"; then
      rm -f "$shim_tmp"
      shim_tmp=
      printf '%s is user-managed; leaving it unchanged.\n' "$vimrc"
      return
    fi

    backup=$(reserve_backup_path)
    # Copy before the atomic replacement.  If either operation fails, the
    # original path is still present and the installer exits without pretending
    # that configuration succeeded.
    if [[ -L $vimrc ]]; then
      backup_command=(cp -Pp "$vimrc" "$backup")
    else
      backup_command=(cp -p "$vimrc" "$backup")
    fi
    if ! "${backup_command[@]}"; then
      rm -f "$backup"
      fail "cannot back up $vimrc"
    fi
    printf 'Backed up the existing .vimrc to %s\n' "$backup"
  fi

  mv "$shim_tmp" "$vimrc" || fail "cannot install $vimrc"
  shim_tmp=
  printf 'Configured %s\n' "$vimrc"
}

sync_plugins() {
  local status report_line

  [[ -r $target/scripts/update_plugins.vim ]] \
    || fail 'the core is ready, but the plugin update helper is missing'
  plugin_log=$(mktemp "${TMPDIR:-/tmp}/onesimus-plugins.XXXXXX.log") \
    || fail 'the core is ready, but a plugin log could not be created'
  plugin_report=$(mktemp "${TMPDIR:-/tmp}/onesimus-plugins.XXXXXX.report") \
    || fail 'the core is ready, but a plugin report could not be created'

  printf 'Synchronizing vim-plug and plugins…\n'
  status=0
  run_with_timeout "${ONESIMUS_PLUGIN_TIMEOUT:-600}" \
    env ONESIMUS_UPDATE_REPORT="$plugin_report" \
    "$vim_bin" -Nu "$target/init.vim" -U NONE -i NONE -n -es \
      --cmd 'let g:onesimus_installing = 1 | let g:onesimus_home_enabled = 0 | let g:onesimus_usage_enabled = 0 | let g:startify_disable_at_vimenter = 1' \
      -S "$target/scripts/update_plugins.vim" \
      </dev/null >"$plugin_log" 2>&1 \
    || status=$?

  report_line=$(sed -n '1p' "$plugin_report")
  if (( status != 0 )) || [[ $report_line != OK ]]; then
    if (( status == 124 )); then
      printf 'plugin synchronization timed out after %ss\n' \
        "${ONESIMUS_PLUGIN_TIMEOUT:-600}" >&2
    elif [[ -s $plugin_report ]]; then
      sed -n '2,24p' "$plugin_report" >&2
    elif [[ -s $plugin_log ]]; then
      sed -n '1,24p' "$plugin_log" >&2
    fi
    fail 'the core is ready, but plugin synchronization failed; rerun the installed install.sh --update to retry'
  fi

  sed -n '2p' "$plugin_report"
  rm -f "$plugin_log" "$plugin_report"
  plugin_log=
  plugin_report=
}

# The checkout is brought to a known-good state before ~/.vimrc is inspected or
# changed.  A failed clone/pull therefore cannot strand the editor configuration.
if (( resume_mode )); then
  validate_resumed_checkout
else
  install_repository
  resume_from_checkout
fi
install_shim

if (( update_mode )); then
  if (( core_only )); then
    printf '\nOnesimus core is updated in %s\n' "$target"
    printf 'Plugins were left unchanged; rerun install.sh --update to synchronize them.\n'
  else
    sync_plugins
    printf '\nOnesimus is updated in %s\n' "$target"
    printf 'Restart any open Vim process to use the new configuration.\n'
    printf 'Retired plugin directories were left untouched; review them with :PlugClean.\n'
  fi
elif (( launch_vim )); then
  # Plugin scripts are discovered during startup.  Installing them from the
  # interactive process would therefore leave the first session subtly less
  # capable than every later one.  Finish all installation work headlessly,
  # then start Vim from a clean process with the complete runtimepath.
  sync_plugins
  printf '\nOnesimus is ready in %s\n' "$target"
  printf 'Opening Vim…\n'
  # exec does not run the shell's EXIT trap; release the installation lock
  # explicitly before replacing this process with the user's editor.
  release_update_lock
  exec "$vim_bin" -Nu "$HOME/.vimrc"
else
  printf '\nOnesimus core is ready in %s\n' "$target"
  printf 'Run %s/install.sh --update when you are ready to synchronize plugins.\n' \
    "$target"
fi
