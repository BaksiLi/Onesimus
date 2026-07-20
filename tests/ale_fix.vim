" ALE fixer integration test.
" Run with:
"   vim -Nu tests/ale_fix.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

let s:result_file = '/tmp/onesimus-ale-fix-result'
let s:finished = 0

function! s:Finish(status, details) abort
  if s:finished
    return
  endif
  let s:finished = 1
  call writefile([a:status] + a:details, s:result_file)
  if a:status ==# 'PASS' || a:status ==# 'SKIP'
    qall!
  endif
  cquit
endfunction

function! s:Fixed() abort
  call assert_equal(['def add(a, b):', '    return a + b'], getline(1, '$'))
  call s:Finish(empty(v:errors) ? 'PASS' : 'FAIL', v:errors)
endfunction

function! s:Timeout(timer) abort
  call s:Finish('FAIL', ['ALEFix did not finish within 8 seconds'])
endfunction

function! s:Start() abort
  if !executable('ruff')
    call s:Finish('SKIP', ['ruff is not installed'])
    return
  endif

  enew
  file /tmp/onesimus-ale-fix-smoke.py
  call setline(1, ['import os', '', 'def add( a,b ):', ' return a+b'])
  setfiletype python
  call assert_equal(['ruff', 'ruff_format', 'remove_trailing_lines',
        \ 'trim_whitespace'], b:ale_fixers)
  OnesimusHealth
  let l:health_popup = popup_list()[-1]
  let l:health = join(getbufline(winbufnr(l:health_popup), 1, '$'), "\n")
  call assert_match('ready\s\+server\s\+pylsp', l:health)
  call popup_close(l:health_popup)
  ALEFix
  call timer_start(8000, function('s:Timeout'))
endfunction

augroup onesimus_ale_fix_test
  autocmd!
  autocmd User ALEFixPost call <SID>Fixed()
  autocmd VimEnter * call <SID>Start() | sleep 9
augroup END
