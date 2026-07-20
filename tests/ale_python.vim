" Optional integration test.  It is skipped when pylsp is unavailable.
" Run with:
"   vim -Nu tests/ale_python.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

let s:result_file = '/tmp/onesimus-ale-python-result'
let s:finished = 0
let s:lsp_started = 0
let s:poll_timer = -1
let s:timeout_timer = -1

function! s:Finish(status, details) abort
  if s:finished
    return
  endif
  let s:finished = 1
  if s:poll_timer >= 0
    call timer_stop(s:poll_timer)
  endif
  if s:timeout_timer >= 0
    call timer_stop(s:timeout_timer)
  endif
  call writefile([a:status] + a:details, s:result_file)
  if a:status ==# 'PASS' || a:status ==# 'SKIP'
    qall!
  endif
  cquit
endfunction

function! s:LSPStarted() abort
  call assert_match('OnesimusTrack.*ale_go_to_definition', maparg('gd', 'n'))
  call assert_equal('', maparg('gi', 'n'),
        \ 'ALE must not replace Vim''s last-insert command')
  call assert_equal('', maparg('gt', 'n'),
        \ 'ALE must not replace Vim''s next-tab command')
  call assert_true(exists('*OnesimusLSPNavigate'))
  call assert_equal('ale#completion#OmniFunc', &l:omnifunc)
  let s:lsp_started = 1
endfunction

function! s:PollDiagnostics(timer) abort
  let l:items = ale#engine#GetLoclist(bufnr(''))
  let l:ruff_items = filter(copy(l:items),
        \ 'get(v:val, ''linter_name'', '''') is# ''ruff''')

  if s:lsp_started && !empty(l:ruff_items)
    call assert_true(index(map(copy(l:ruff_items),
          \ 'get(v:val, ''code'', '''')'), 'F401') >= 0,
          \ 'Ruff reports the unused import')
    call s:Finish(empty(v:errors) ? 'PASS' : 'FAIL', v:errors)
  endif
endfunction

function! s:Timeout(timer) abort
  call s:Finish('FAIL', ['ALE LSP/diagnostics did not become ready within 8 seconds'])
endfunction

function! s:Start() abort
  let l:pylsp = get(g:, 'ale_python_pylsp_executable', 'pylsp')
  if !executable(l:pylsp)
    call s:Finish('SKIP', ['pylsp is not installed'])
    return
  endif
  if !executable('ruff')
    call s:Finish('SKIP', ['ruff is not installed'])
    return
  endif

  enew
  file /tmp/onesimus-ale-smoke.py
  call setline(1, ['import os', '', 'def greeting(name: str) -> str:',
        \ '    return "Hello " + name'])
  setfiletype python
  ALELint
  let s:poll_timer = timer_start(50, function('s:PollDiagnostics'),
        \ {'repeat': -1})
  let s:timeout_timer = timer_start(8000, function('s:Timeout'))
endfunction

augroup onesimus_ale_python_test
  autocmd!
  autocmd User ALELSPStarted call <SID>LSPStarted()
  autocmd VimEnter * call <SID>Start() | sleep 9
augroup END
