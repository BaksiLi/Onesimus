" The browser PDF follows the cursor only through a reader already open for
" this PDF, and quietly skips lines without a SyncTeX position.
" Run with:
"   vim -Nu tests/tex_follow.vim -i NONE -n -es
let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:vimtex_enabled = 0
let g:onesimus_usage_enabled = 0
let g:startify_disable_at_vimenter = 1
let g:onesimus_tex_browser_port = 0
" Serve without opening a browser, as over SSH.
let $SSH_CONNECTION = 'follow test'
execute 'source '.fnameescape($MYVIMDOT)
" After init: a personal custom/settings.vim may name a relay host.
let g:webpreview_host = '127.0.0.1'

let s:root = tempname()
call mkdir(s:root, 'p')
call writefile(['\documentclass{article}', '\begin{document}', 'One.', '\end{document}'], s:root.'/main.tex')
" A complete PDF without SyncTeX data: every forward position misses.
call writefile(['%PDF-1.4', 'follow', '%%EOF'], s:root.'/main.pdf')

function! s:Messages(pattern) abort
  return len(filter(split(execute('messages'), "\n"), 'v:val =~# a:pattern'))
endfunction

function! s:Wait(condition) abort
  for l:attempt in range(250)
    if eval(a:condition) | return 1 | endif
    sleep 20m
  endfor
  return 0
endfunction

function! s:Run() abort
  execute 'edit '.fnameescape(s:root.'/main.tex')
  let l:pdf = s:root.'/main.pdf'
  let l:main = expand('%:p')
  let l:position = {'file': l:main, 'line': 3, 'column': 1}
  call assert_false(OnesimusTexBrowserFollow(l:pdf, l:main, l:position),
        \ 'following must not start a reader')
  call assert_true(OnesimusTexBrowser(l:pdf, l:main, {'show': 0}))
  call assert_true(s:Wait('s:Messages(''http://127\.0\.0\.1:'') > 0'), 'the reader reports its URL')
  call assert_false(OnesimusTexBrowserFollow(s:root.'/other.pdf', l:main, l:position),
        \ 'following must not retarget another PDF')

  messages clear
  call assert_true(OnesimusTexToggleFollow())
  call assert_true(OnesimusTexBrowserFollow(l:pdf, l:main, l:position))
  call cursor(4, 1)
  doautocmd CursorHold
  sleep 600m
  call assert_equal(0, s:Messages('PDF POSITION'), 'missed follow positions stay quiet')

  " An explicit locate still reports why it could not move the PDF.
  call OnesimusTexLocatePDF()
  call assert_true(s:Wait('s:Messages(''PDF POSITION'') > 0'), 'an explicit locate reports a miss')
  call assert_false(OnesimusTexToggleFollow())
  call OnesimusTexBrowserStop()

  if !empty(v:errors)
    call writefile(v:errors, '/dev/stderr')
    cquit
  endif
  qall!
endfunction

autocmd VimEnter * ++nested call s:Run()
