" Native status and tab lines: vim -Nu tests/statusline.vim -i NONE -n -es
let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)
let g:ale_linters = {}

function! s:Check(ok, what) abort
  if !a:ok
    call add(s:errors, a:what)
  endif
endfunction

function! s:Run() abort
  let s:errors = []
  set columns=80
  let l:dir = tempname()
  call mkdir(l:dir)
  execute 'edit '.fnameescape(l:dir.'/notes.md')
  call setline(1, 'One two three four.')
  setfiletype markdown
  doautocmd TextChanged
  let g:statusline_winid = win_getid()
  let l:line = OnesimusStatusline()
  " Ex mode reports COMMAND; the block's colour group is what matters here.
  call s:Check(l:line =~# '^%#OnesimusMode\a\+# \u', 'mode block: '.l:line)
  call s:Check(l:line =~# '%f', 'file name: '.l:line)
  call s:Check(l:line =~# '4 words', 'prose word count: '.l:line)
  call s:Check(l:line !~# 'utf-8', 'default encoding stays hidden: '.l:line)

  doautocmd VimEnter
  call s:Check(&showtabline == 0, 'tab line hidden with one buffer')
  for l:name in ['alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta']
    execute 'badd '.fnameescape(l:dir.'/'.l:name.'_with_a_long_name.tex')
  endfor
  call s:Check(&showtabline == 2, 'tab line shown with several buffers')
  execute 'buffer '.bufnr(l:dir.'/delta_with_a_long_name.tex')
  set columns=60
  let l:tabs = OnesimusTabline()
  call s:Check(l:tabs =~# 'TabLineSel# delta_with_a_long_name.tex',
        \ 'current buffer visible in a narrow tab line: '.l:tabs)
  call s:Check(l:tabs =~# '‹' && l:tabs =~# '›', 'both sides marked as cut')

  if empty(s:errors)
    qall!
  endif
  call writefile(s:errors, '/dev/stderr')
  cquit
endfunction

call s:Run()
