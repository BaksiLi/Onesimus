" Asynchronous in-editor update integration test.
" Run with:
"   vim -Nu tests/update.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 1
let g:onesimus_usage_state_dir = '/tmp/onesimus-update-usage-'.getpid()
execute 'source '.fnameescape($MYVIMDOT)

let g:onesimus_test_popup_supported = 1
let g:onesimus_test_update_popup = {}

function! OnesimusPopupSupported() abort
  return g:onesimus_test_popup_supported
endfunction

function! OnesimusPopup(title, lines) abort
  let g:onesimus_test_update_popup = {
        \ 'title': a:title,
        \ 'lines': copy(a:lines),
        \ }
  return 1
endfunction

function! OnesimusNotify(title, lines, failed) abort
  let g:onesimus_test_update_popup = {
        \ 'title': a:title,
        \ 'lines': copy(a:lines),
        \ 'failed': a:failed,
        \ }
  echomsg a:title
  for l:line in a:lines
    echomsg l:line
  endfor
  return 1
endfunction

function! s:WaitForUpdate() abort
  let l:checks = 0
  while get(g:onesimus_update_state, 'running', 0) && l:checks < 500
    sleep 10m
    let l:checks += 1
  endwhile
  call assert_false(get(g:onesimus_update_state, 'running', 0),
        \ 'the update job finishes within five seconds')
endfunction

function! s:WriteUpdater(path, lines) abort
  call writefile(['#!/bin/sh', 'set -eu'] + a:lines, a:path)
  call setfperm(a:path, 'rwx------')
endfunction

function! s:RunUpdateTests() abort
  let l:root = tempname().' onesimus update'
  call mkdir(l:root, 'p')
  let l:installer = l:root.'/install.sh'
  let l:count = l:root.'/runs'
  let $VIMRCDIR = l:root

  call s:WriteUpdater(l:installer, [
        \ 'root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)',
        \ 'printf "run\\n" >> "$root/runs"',
        \ 'printf "updated checkout\\n"',
        \ 'printf "network note\\n" >&2',
        \ 'printf "%s\\n" "$ONESIMUS_VIM_BIN" > "$root/vim-bin"',
        \ 'printf "%s\\n" "$ONESIMUS_PLUGIN_HOME" > "$root/plugin-home"',
        \ 'printf "%s\\n" "$ONESIMUS_VIM_PLUG" > "$root/vim-plug"',
        \ 'printf "%s\\n" "let g:onesimus_test_reloaded = 1" > "$root/init.vim"',
        \ ])

  OnesimusUpdate
  OnesimusUpdate
  call s:WaitForUpdate()
  call assert_equal(['run'], readfile(l:count),
        \ 'a second invocation never starts a concurrent updater')
  call assert_equal(0, g:onesimus_update_state.exit_status)
  call assert_equal(['updated checkout'], g:onesimus_update_state.stdout)
  call assert_equal(['network note'], g:onesimus_update_state.stderr)
  call assert_equal(fnamemodify(v:progpath, ':p'), readfile(l:root.'/vim-bin')[0],
        \ 'the updater reuses the Vim build that launched it')
  call assert_equal(g:onesimus_plugin_home,
        \ readfile(l:root.'/plugin-home')[0],
        \ 'the updater preserves the configured plugin directory')
  call assert_equal(g:onesimus_vim_plug, readfile(l:root.'/vim-plug')[0],
        \ 'the updater preserves the configured vim-plug path')
  call assert_match('ONESIMUS / UPDATE',
        \ get(g:onesimus_test_update_popup, 'title', ''))
  call assert_match('Restart Vim',
        \ join(get(g:onesimus_test_update_popup, 'lines', []), "\n"))
  call assert_false(get(g:onesimus_test_update_popup, 'failed', 1),
        \ 'a successful background update uses a non-error notification')
  call assert_false(exists('g:onesimus_test_reloaded'),
        \ 'updating files never reloads the active Vim process')
  call assert_equal(1, g:onesimus_usage_runtime.counts['meta.update'],
        \ 'only a launched update is tracked')

  call s:WriteUpdater(l:installer, [
        \ 'printf "local changes block fast-forward\\n"',
        \ 'printf "resolve the branch first\\n" >&2',
        \ 'exit 7',
        \ ])
  let g:onesimus_test_popup_supported = 0
  silent messages clear
  OnesimusUpdate
  call s:WaitForUpdate()
  let l:messages = execute('messages')
  call assert_equal(7, g:onesimus_update_state.exit_status)
  call assert_true(get(g:onesimus_test_update_popup, 'failed', 0),
        \ 'a failed background update is marked as an error notification')
  call assert_match('Update failed (exit 7)', l:messages)
  call assert_match('local changes block fast-forward', l:messages)
  call assert_match('resolve the branch first', l:messages)
  call assert_match(':OnesimusUpdate again', l:messages)
  call assert_equal(2, g:onesimus_usage_runtime.counts['meta.update'])

  let l:actions = OnesimusHomeActions()
  call assert_true(index(map(copy(l:actions), 'v:val.cmd'),
        \ 'OnesimusUpdate') >= 0)
  call assert_equal('u', g:startify_lists[0].indices[-1])

  let g:onesimus_usage_enabled = 0
  call delete(g:onesimus_usage_state_dir, 'rf')
  call delete(l:root, 'rf')
  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_update_test
  autocmd!
  autocmd VimEnter * call <SID>RunUpdateTests()
augroup END
