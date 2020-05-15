func! s:ToggleBackground()
  if &background ==? 'dark'
    set background=light
  else
    set background=dark
  endif
endfunc

command ToggleBackground call <sid>ToggleBackground()
