" AutoCorrect integration: CJK spacing diagnostics in TeX, and F6's fixer
" leaving Markdown code alone. Skipped unless autocorrect is installed.
" Run with:
"   vim -Nu tests/ale_autocorrect.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

let s:result_file = '/tmp/onesimus-ale-autocorrect-result'
let s:dir = fnamemodify(tempname(), ':h')
let s:finished = 0
let s:polls = 0

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

function! s:Linted(timer) abort
  let s:polls += 1
  let l:ours = filter(copy(ale#engine#GetLoclist(bufnr(''))),
        \ 'v:val.linter_name ==# ''autocorrect''')
  if empty(l:ours) && s:polls < 80
    return
  endif
  call timer_stop(a:timer)
  " Only the prose line: math, commands and citations are not copy.
  call assert_equal([[1, 'CJK spacing: 在 Vim 中排版，很好用。']],
        \ map(l:ours, '[v:val.lnum, v:val.text]'))
  execute 'edit' fnameescape(s:dir.'/autocorrect.md')
  call setline(1, ['在Vim中排版', '```python', 'x = "中文abc"', '```'])
  ALEFix
endfunction

function! s:Fixed() abort
  if &filetype !=# 'markdown'
    return
  endif
  call assert_equal(['在 Vim 中排版', '```python', 'x = "中文abc"', '```'],
        \ getline(1, '$'))
  call s:Finish(empty(v:errors) ? 'PASS' : 'FAIL', v:errors)
endfunction

function! s:Start() abort
  if !executable('autocorrect')
    call s:Finish('SKIP', ['autocorrect is not installed'])
    return
  endif
  execute 'edit' fnameescape(s:dir.'/autocorrect.tex')
  call setline(1, ['在Vim中排版,很好用。',
        \ '波數$k_g(\omega)$見式~\eqref{eq:x}與~\cite{a}。'])
  let b:ale_linters = ['autocorrect']
  ALELint
  call timer_start(100, function('s:Linted'), {'repeat': -1})
  call timer_start(10000, {-> s:Finish('FAIL', ['timed out'] + v:errors)})
endfunction

augroup onesimus_ale_autocorrect_test
  autocmd!
  autocmd User ALEFixPost call <SID>Fixed()
  autocmd VimEnter * ++nested call <SID>Start() | sleep 11
augroup END
