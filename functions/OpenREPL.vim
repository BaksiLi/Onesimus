" TODO: Rename functions
" TODO: for GFM (py-gfm), ask to install if not configured
" TODO: Separate selection and core
" Use term_start()
" https://github.com/rhysd/reply.vim
" https://github.com/vlime/vlime

if exists('g:loaded_OpenREPL')
  finish
endif

let g:loaded_OpenREPL = 1

" For OpenREPL
function! s:OpenREPL()
  if &filetype ==? 'python'
    exec 'terminal python'
  elseif &filetype ==? 'ruby'
    exec 'terminal irb'
  elseif &filetype ==? 'scheme'
    "exec 'terminal mit-scheme'
    exec 'terminal chez'
  elseif &filetype ==? 'haskell'
    exec 'terminal ghci'

  elseif &filetype ==? 'vim'
    normal! gQ
  endif
endfunction

command! OpenREPL call <sid>OpenREPL()

" For Visual
function! s:OpenREPLfor() range
  echo 'Passed lines <'.a:firstline.','.a:lastline.'>'

  let lines = getline(a:firstline,a:lastline)
  let text = join(lines, '\n')

endfunction

command! -range OpenREPLfor <line1>,<line2>call <sid>OpenREPLfor()
