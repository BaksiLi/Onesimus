" Focused writing mode with reversible state.

let g:onesimus_wordproc_state = get(g:, 'onesimus_wordproc_state', {})

function! s:SaveOptions() abort
  return {
        \ 'winid': win_getid(),
        \ 'number': &l:number,
        \ 'relativenumber': &l:relativenumber,
        \ 'textwidth': &l:textwidth,
        \ 'cursorline': &l:cursorline,
        \ 'wrap': &l:wrap,
        \ 'linebreak': &l:linebreak,
        \ 'spell': &l:spell,
        \ 'plugins': PlugInstalled('goyo.vim')
        \   && PlugInstalled('limelight.vim')
        \   && exists(':Goyo') && exists(':Limelight'),
        \ 'goyo_active': exists('t:goyo_revert'),
        \ 'limelight_active': exists('#limelight'),
        \ 'enabled_goyo': 0,
        \ 'enabled_limelight': 0,
        \ }
endfunction

function! s:RestoreOptions(state) abort
  if has_key(a:state, 'winid') && win_id2win(a:state.winid) > 0
    call win_gotoid(a:state.winid)
  endif
  for l:option in ['number', 'relativenumber', 'textwidth', 'cursorline',
        \ 'wrap', 'linebreak', 'spell']
    if has_key(a:state, l:option)
      execute 'let &l:'.l:option.' = '.string(a:state[l:option])
    endif
  endfor
endfunction

function! s:Enable() abort
  let l:state = s:SaveOptions()

  if l:state.plugins
    if !l:state.goyo_active
      silent Goyo
      let l:state.enabled_goyo = 1
    endif
    if !l:state.limelight_active
      silent Limelight
      let l:state.enabled_limelight = 1
    endif
  else
    setlocal nonumber norelativenumber nocursorline
    setlocal textwidth=80 wrap linebreak
  endif
  let g:onesimus_wordproc_state = l:state
  echomsg 'Word processing mode on.'
endfunction

function! s:Disable() abort
  let l:state = copy(g:onesimus_wordproc_state)
  if get(l:state, 'enabled_limelight', 0) && exists(':Limelight')
    silent! Limelight!
  endif
  if get(l:state, 'enabled_goyo', 0) && exists(':Goyo')
    silent! Goyo!
  endif
  call s:RestoreOptions(l:state)
  let g:onesimus_wordproc_state = {}
  echomsg 'Word processing mode off.'
endfunction

function! s:ToggleWordProcessingMode() abort
  if empty(g:onesimus_wordproc_state)
    call s:Enable()
  else
    call s:Disable()
  endif
  if exists('*OnesimusTrack')
    call OnesimusTrack('writing.focus')
  endif
endfunction

command! WPModeToggle call <SID>ToggleWordProcessingMode()
