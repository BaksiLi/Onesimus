" Focus changes only presentation; source-layout and spelling are independent.

let g:onesimus_wordproc_state = get(g:, 'onesimus_wordproc_state', {})

function! OnesimusWritingFocusActive() abort
  return !empty(g:onesimus_wordproc_state)
endfunction

function! s:SaveView() abort
  let l:view = {'winid': win_getid(), 'bufnr': bufnr(''), 'options': {}}
  for l:option in ['number', 'relativenumber', 'cursorline', 'wrap',
        \ 'linebreak', 'breakindent', 'showbreak']
    let l:view.options[l:option] = eval('&l:'.l:option)
  endfor
  return l:view
endfunction

function! s:RestoreView(state) abort
  let l:view = get(a:state, 'view', {})
  if empty(l:view)
    return
  endif
  let l:windows = getwininfo(l:view.winid)
  if !empty(l:windows) && l:windows[0].bufnr == l:view.bufnr
    let l:commands = []
    for [l:option, l:value] in items(l:view.options)
      call add(l:commands, 'let &l:'.l:option.' = '.string(l:value))
    endfor
    " Restoring another window must not switch tabs (which can close Goyo),
    " or apply the old buffer's settings to a different draft.
    call win_execute(l:view.winid, join(l:commands, ' | '))
  endif
  let a:state.view = {}
endfunction

function! s:Enable() abort
  let l:state = {'enabled_goyo': 0, 'enabled_limelight': 0}
  if PlugInstalled('goyo.vim') && exists(':Goyo') && !exists('t:goyo_revert')
    silent Goyo
    let l:state.enabled_goyo = 1
    let l:state.goyo_win = win_getid()
  endif
  if PlugInstalled('limelight.vim') && exists(':Limelight') && !exists('#limelight')
    silent Limelight
    let l:state.enabled_limelight = 1
  endif

  " Snapshot the window we actually modify: Goyo creates a temporary tab.
  let l:state.view = s:SaveView()
  setlocal nonumber norelativenumber nocursorline wrap linebreak breakindent
  let &l:showbreak = '↳ '
  let g:onesimus_wordproc_state = l:state
  echomsg 'Word processing mode on.'
endfunction

function! s:Disable() abort
  let l:state = g:onesimus_wordproc_state
  " GoyoLeave/BufLeave can fire during teardown.  Release ownership first.
  let g:onesimus_wordproc_state = {}
  call s:RestoreView(l:state)
  if get(l:state, 'enabled_limelight', 0) && exists(':Limelight')
    silent! Limelight!
  endif
  if get(l:state, 'enabled_goyo', 0) && exists(':Goyo')
        \ && win_id2tabwin(l:state.goyo_win)[0] == tabpagenr()
        \ && exists('t:goyo_revert')
    silent! Goyo!
  endif
  echomsg 'Word processing mode off.'
endfunction

function! s:LeaveView() abort
  let l:state = g:onesimus_wordproc_state
  let l:view = get(l:state, 'view', {})
  if empty(l:view) || l:view.winid != win_getid() || l:view.bufnr != bufnr('')
    return
  endif
  " Vim remembers window options for hidden buffers.  Restore before leaving,
  " while this window still displays the draft whose options were borrowed.
  call s:RestoreView(l:state)
  if !get(l:state, 'enabled_goyo', 0)
    call s:Disable()
  endif
endfunction

augroup onesimus_writing_focus
  autocmd!
  autocmd BufLeave,WinLeave * call <SID>LeaveView()
  autocmd User GoyoLeave if get(g:onesimus_wordproc_state, 'enabled_goyo', 0)
        \ | call <SID>Disable() | endif
augroup END

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

call one#define('focus', '*', function('s:ToggleWordProcessingMode'))
