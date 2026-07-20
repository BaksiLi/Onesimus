func! s:ToggleBackground()
  if &background ==? 'dark'
    set background=light
  else
    set background=dark
  endif
  if exists('*OnesimusTrack')
    call OnesimusTrack('ui.background')
  endif
endfunc

command! ToggleBackground call <sid>ToggleBackground()
