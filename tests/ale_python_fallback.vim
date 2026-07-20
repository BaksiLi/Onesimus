" Python formatting falls back cleanly when Ruff is not on PATH.
" Run with:
"   vim -Nu tests/ale_python_fallback.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let $PATH = '/usr/bin:/bin'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

function! s:RunFallbackTests() abort
  enew
  file /tmp/onesimus-python-fallback.py
  setfiletype python

  call assert_true(exists('b:ale_fixers'))
  call assert_true(index(b:ale_fixers, 'ruff') < 0)
  call assert_equal(['remove_trailing_lines', 'trim_whitespace'],
        \ b:ale_fixers)

  setlocal filetype=text
  call assert_false(exists('b:ale_fixers'),
        \ 'Python buffer-local fixers are cleared on filetype change')

  call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors,
        \ '/tmp/onesimus-ale-python-fallback-result')
  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_ale_python_fallback_test
  autocmd!
  autocmd VimEnter * call <SID>RunFallbackTests()
augroup END
