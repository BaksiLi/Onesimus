" TODO: copy visual section to the terminal
" TODO: for GFM (py-gfm), ask to install if not configured
" TODO: take an optional argument
" https://github.com/sillybun/vim-repl

function! s:OpenREPL()
  if &filetype ==? 'python'
    exec 'terminal python'
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
