" Optional integration test.  It is skipped unless Cogitatum's editor runtime
" and CLI are installed (see custom/plugins.vim.example).
" Run with:
"   vim -Nu tests/ale_cogitatum.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

let s:result_file = '/tmp/onesimus-ale-cogitatum-result'
let s:file = '/tmp/onesimus-cogitatum-smoke.cog.md'
let s:stage = 'broken'
let s:finished = 0
let s:poll_timer = -1
let s:requested = 0

function! s:Finish(status, details) abort
  if s:finished
    return
  endif
  let s:finished = 1
  call timer_stop(s:poll_timer)
  call writefile([a:status] + a:details, s:result_file)
  if a:status ==# 'PASS' || a:status ==# 'SKIP'
    qall!
  endif
  cquit
endfunction

function! s:Codes() abort
  return map(copy(ale#engine#GetLoclist(bufnr(''))), 'get(v:val, ''code'', '''')')
endfunction

" One poll drives the stages: diagnostics, a corrected revision, then a jump.
function! s:Poll(timer) abort
  if s:stage ==# 'broken' && index(s:Codes(), 'UNKNOWN_TARGET') >= 0
    let s:stage = 'fixed'
    call setline(3, '  - [G +> @claim] Known.')
    ALELint
  elseif s:stage ==# 'fixed' && empty(s:Codes())
    let s:stage = 'jump'
    call cursor(3, 13)
  elseif s:stage ==# 'jump' && line('.') == 1
    call assert_equal(7, col('.'), 'definition lands on the declared name')
    call s:Finish(empty(v:errors) ? 'PASS' : 'FAIL', v:errors)
  elseif s:stage ==# 'jump' && !s:requested
    " Navigation becomes available once ALE reports the server started.
    let s:requested = OnesimusLSPNavigate('definition')
  endif
endfunction

function! s:Start() abort
  if empty(globpath(&runtimepath, 'ale_linters/cogitatum/cog.vim'))
    call s:Finish('SKIP', ['Cogitatum''s editor runtime is not installed'])
    return
  endif
  call assert_equal(['cog'], g:ale_linters.cogitatum)
  call assert_true(index(g:ale_linters.markdown, 'cog') >= 0)
  call assert_true(index(g:markdown_fenced_languages, 'cog=cogitatum') >= 0)

  call writefile(['- [C @claim] A claim.', '  - [G use @claim; @route] Because.',
        \ '  - [G +> @missing] Unknown.'], s:file)
  execute 'edit '.fnameescape(s:file)
  " Onesimus lints the first file after the screen is drawn, so its linter
  " definitions (and their variables) are not loaded yet at VimEnter.
  call ale#linter#Get(&filetype)
  if !executable(cogitatum#ale#Executable(bufnr('')))
    call s:Finish('SKIP', ['the cog CLI is not installed'])
    return
  endif
  call assert_equal('cogitatum', &filetype)
  call assert_equal('cogClaim', synIDattr(synID(1, 4, 1), 'name'))
  call assert_equal('cogName', synIDattr(synID(2, 13, 1), 'name'))
  ALELint
  let s:poll_timer = timer_start(50, function('s:Poll'), {'repeat': -1})
  call timer_start(8000, {-> s:Finish('FAIL',
        \ ['ALE did not complete the '.s:stage.' stage within 8 seconds'] + v:errors)})
endfunction

augroup onesimus_ale_cogitatum_test
  autocmd!
  autocmd VimEnter * ++nested call <SID>Start() | sleep 9
augroup END
