function! WinMove(key)
  let t:curwin = winnr()
  exec "wincmd ".a:key
  if (t:curwin == winnr()) "we havent moved
    if (match(a:key,'[jk]')) "were we going up/down
      wincmd v
    else
      wincmd s
    endif
    exec "wincmd ".a:key
  endif
endfunction


" closing, rotating and moving
map <leader>wq :wincmd q<cr>
map <leader>wr <C-W>r

" Resizing windows
nmap <leader>s<left>    :3wincmd ><cr>
nmap <leader>s<right>   :3wincmd <<cr>
nmap <leader>s<up>      :3wincmd +<cr>
nmap <leader>s<down>    :3wincmd -<cr>

nmap <leader><left>     :wincmd h<cr>
nmap <leader><down>     :wincmd j<cr>
nmap <leader><up>       :wincmd k<cr>
nmap <leader><right>    :wincmd l<cr>
