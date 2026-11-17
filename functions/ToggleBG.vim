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

call one#define('background', '*', function('s:ToggleBackground'))
