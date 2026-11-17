" The popup behind \ and \\.  Its rows come from autoload/one.vim, so every
" row is also a real mapping and a `:One` verb; this file only draws them.

let s:guides = {}
let s:active_guide = -1
let s:notification = get(s:, 'notification', -1)

function! OnesimusPopupSupported() abort
  " Vim's popup API arrived incrementally.  8.1.1561 is the first patch with
  " every operation used below, including popup_setoptions().
  return has('patch-8.1.1561')
        \ && exists('*popup_create')
        \ && exists('*popup_getoptions')
        \ && exists('*popup_setoptions')
        \ && exists('*popup_settext')
endfunction

function! s:Installed(name) abort
  return exists('*PlugInstalled') && PlugInstalled(a:name)
endfunction

function! s:InGitRepository() abort
  let l:start = empty(expand('%:p')) ? getcwd() : expand('%:p:h')
  return !empty(finddir('.git', l:start.';'))
        \ || !empty(findfile('.git', l:start.';'))
endfunction

function! s:Menu(title, rows, ...) abort
  return {'title': a:title, 'summary': get(a:000, 0, ''),
        \ 'items': map(copy(a:rows),
        \   {_, row -> {'key': row[0], 'command': row[1], 'label': row[2]}})}
endfunction

function! s:Writing() abort
  return OnesimusIsWritingBuffer(bufnr('%'))
endfunction

function! s:Conflict() abort
  return exists('*OnesimusHasExternalConflict') && OnesimusHasExternalConflict()
endfunction

function! s:Kind() abort
  return &l:filetype ==# 'tex' ? 'TeX paper'
        \ : (&l:filetype ==# 'bib' ? 'Bibliography'
        \ : (&l:filetype ==# 'markdown' ? 'Markdown'
        \ : (&l:filetype ==# 'cogitatum' ? 'Cogitatum inquiry'
        \ : (s:Writing() ? 'Writing' : 'Current buffer'))))
endfunction

function! s:ContextTitle() abort
  let l:title = toupper(s:Kind())
  if s:Conflict()
    return l:title.' · DISK CONFLICT'
  endif
  return l:title.(empty(bufname('%')) ? '' : ' · '.expand('%:t'))
endfunction

function! s:ContextMenu() abort
  let l:summary = s:Conflict() ? 'Compare before choosing a version.'
        \ : (&l:filetype ==# 'tex' && exists('*OnesimusTexMenuSummary')
        \   ? OnesimusTexMenuSummary()
        \ : (s:Writing() ? (&l:modified ? 'Unsaved edits' : 'No unsaved edits') : ''))
  let l:rows = &l:buftype ==# '' ? one#file_menu() : []
  return s:Menu(s:ContextTitle(), l:rows, l:summary)
endfunction

function! s:GlobalMenu() abort
  let l:items = []
  let l:file = s:ContextMenu()
  if !empty(l:file.items)
    call add(l:items, {'key': '\', 'label': 'This file · '.s:Kind(), 'menu': l:file})
  endif
  for [l:key, l:title, l:rows] in one#global_menu()
    if (l:key ==# 'f' && !s:Installed('vim-clap'))
          \ || (l:key ==# 'g' && !(s:Installed('vim-fugitive') && s:InGitRepository()))
      continue
    endif
    call add(l:items, {'key': l:key, 'label': l:title,
          \ 'menu': s:Menu(toupper(l:title), l:rows)})
  endfor
  call add(l:items, {'key': '?', 'label': 'Manual', 'command': 'One manual'})
  return {'title': 'ACTIONS', 'summary': ':One <Tab> lists every action',
        \ 'items': l:items}
endfunction

function! s:MenuLines(menu, depth, ...) abort
  let l:selected = get(a:000, 0, -1)
  let l:lines = ['  '.a:menu.title, '  '.get(a:menu, 'summary', '')]
  for l:index in range(len(a:menu.items))
    let l:item = a:menu.items[l:index]
    call add(l:lines, printf('%s %-2s  %s%s',
          \ l:index == l:selected ? '>' : ' ', l:item.key, l:item.label,
          \ has_key(l:item, 'menu') ? '  >' : ''))
  endfor
  call extend(l:lines, ['', '  ↑↓ select · Enter/tap · Esc'])
  return l:lines
endfunction

function! s:PopupWidth(lines) abort
  let l:width = 28
  for l:line in a:lines
    let l:width = max([l:width, strdisplaywidth(l:line)])
  endfor
  return min([l:width, max([20, &columns - 8])])
endfunction

function! OnesimusPopupFilter(id, key) abort
  if index(["q", "\<Esc>", "\<CR>", " "], a:key) >= 0
    call popup_close(a:id)
    return 1
  elseif index(["j", "\<Down>", "\<C-D>"], a:key) >= 0
    let l:options = popup_getoptions(a:id)
    call popup_setoptions(a:id, {
          \ 'firstline': get(l:options, 'firstline', 1)
          \   + (a:key ==# "\<C-D>" ? 5 : 1),
          \ })
    return 1
  elseif index(["k", "\<Up>", "\<C-U>"], a:key) >= 0
    let l:options = popup_getoptions(a:id)
    call popup_setoptions(a:id, {
          \ 'firstline': max([1, get(l:options, 'firstline', 1)
          \   - (a:key ==# "\<C-U>" ? 5 : 1)]),
          \ })
    return 1
  endif
  " A diagnostic popup may appear after an asynchronous job.  Unknown keys
  " must continue to the editor instead of eating the user's next action.
  return 0
endfunction

function! OnesimusPopup(title, lines) abort
  let l:lines = ['  '.a:title, ''] + copy(a:lines)
        \ + ['', '  j / k scroll  ·  q / Esc close']
  if !OnesimusPopupSupported()
    for l:line in l:lines
      echomsg l:line
    endfor
    return -1
  endif
  let l:borderchars = &encoding ==# 'utf-8'
        \ ? ['─', '│', '─', '│', '┌', '┐', '┘', '└']
        \ : ['-', '|', '-', '|', '+', '+', '+', '+']
  return popup_create(l:lines, {
        \ 'pos': 'center',
        \ 'minwidth': s:PopupWidth(l:lines),
        \ 'maxwidth': max([20, &columns - 8]),
        \ 'maxheight': max([6, &lines - 6]),
        \ 'padding': [0, 1, 0, 1],
        \ 'border': [1, 1, 1, 1],
        \ 'borderchars': l:borderchars,
        \ 'borderhighlight': ['Comment'],
        \ 'highlight': 'Pmenu',
        \ 'mapping': 0,
        \ 'filter': function('OnesimusPopupFilter'),
        \ 'filtermode': 'n',
        \ 'close': 'click',
        \ 'scrollbar': 1,
        \ 'wrap': 0,
        \ 'zindex': 210,
        \ })
endfunction

function! OnesimusNotify(title, lines, failed) abort
  let l:lines = ['  '.a:title, ''] + copy(a:lines)

  " Keep the complete result in :messages even when the transient notification
  " is too small to show every diagnostic line.
  redraw
  if a:failed
    echohl ErrorMsg
  else
    echohl MoreMsg
  endif
  echomsg a:title
  echohl None
  for l:line in a:lines
    echomsg l:line
  endfor

  if !OnesimusPopupSupported() || !exists('*popup_notification')
    return -1
  endif
  let l:preview = l:lines[:10]
  if len(l:lines) > len(l:preview)
    call extend(l:preview, ['', '  Full output: :messages'])
  endif
  " Progress and its result occupy the same place, including after a reload.
  call popup_close(s:notification)
  let s:notification = popup_notification(l:preview, {
        \ 'time': a:failed ? 12000 : 6000,
        \ 'minwidth': s:PopupWidth(l:preview),
        \ 'maxwidth': max([20, &columns - 8]),
        \ 'maxheight': max([6, min([14, &lines - 4])]),
        \ 'highlight': a:failed ? 'ErrorMsg' : 'MoreMsg',
        \ 'border': [1, 1, 1, 1],
        \ 'borderhighlight': [a:failed ? 'ErrorMsg' : 'MoreMsg'],
        \ 'close': 'click',
        \ 'mapping': 1,
        \ })
  return s:notification
endfunction

function! s:GuideClosed(id, result) abort
  let l:state = get(s:guides, string(a:id), {})
  if has_key(l:state, 'original_mouse')
    let &mouse = l:state.original_mouse
  endif
  if !empty(l:state)
    call remove(s:guides, string(a:id))
  endif
  if s:active_guide == a:id
    let s:active_guide = -1
  endif
endfunction

function! s:VisibleMenu(stack) abort
  let l:menu = copy(a:stack[-1])
  let l:menu.items = copy(l:menu.items)
  if len(a:stack) > 1
    " Back is an actual row: a touch user must not need a keyboard to leave
    " a submenu.  Keep it in the same hit-testing/selection model as actions.
    call insert(l:menu.items, {'key': '<', 'label': 'Back', 'back': 1})
  endif
  return l:menu
endfunction

function! s:RenderGuide(id) abort
  let l:state = get(s:guides, string(a:id), {})
  if empty(l:state)
    return
  endif
  let l:menu = s:VisibleMenu(l:state.stack)
  let l:selected = get(l:state.selected, -1, 0)
  let l:lines = s:MenuLines(l:menu, len(l:state.stack), l:selected)
  call popup_settext(a:id, l:lines)
  call popup_setoptions(a:id, {
        \ 'minwidth': s:PopupWidth(l:lines),
        \ 'maxwidth': max([20, &columns - 8]),
        \ 'wrap': 0,
        \ })
  " Keep the highlighted item in view on short SSH/touch terminals.
  let l:position = popup_getpos(a:id)
  let l:item_line = l:selected + 3
  let l:firstline = get(l:position, 'firstline', 1)
  let l:height = max([1, get(l:position, 'core_height', 1)])
  " wrap=0 gives exactly one buffer line per screen row.  lastline can still
  " describe the previous paint immediately after popup_settext().
  let l:lastline = l:firstline + l:height - 1
  if l:item_line < l:firstline
    call popup_setoptions(a:id, {'firstline': max([1, l:item_line - 1])})
  elseif l:item_line > l:lastline
    call popup_setoptions(a:id,
          \ {'firstline': max([1, l:item_line - l:height + 2])})
  endif
endfunction

function! s:MouseItemIndex(id, state) abort
  if !exists('*getmousepos')
    return -1
  endif
  let l:mouse = getmousepos()
  if get(l:mouse, 'winid', 0) != a:id
    return -1
  endif
  let l:index = get(l:mouse, 'line', 0) - 3
  return l:index >= 0 && l:index < len(s:VisibleMenu(a:state.stack).items)
        \ ? l:index : -1
endfunction

function! s:GuideBack(id) abort
  let l:state = get(s:guides, string(a:id), {})
  if len(get(l:state, 'stack', [])) <= 1
    call popup_close(a:id)
    return
  endif
  call remove(l:state.stack, -1)
  call remove(l:state.selected, -1)
  let l:state.mouse_pressed = -1
  let s:guides[string(a:id)] = l:state
  call popup_setoptions(a:id, {'firstline': 1})
  call s:RenderGuide(a:id)
endfunction

function! s:RunGuideItem(id, item) abort
  let l:state = get(s:guides, string(a:id), {})
  if empty(l:state)
    return
  endif
  if get(a:item, 'back', 0)
    call s:GuideBack(a:id)
    return
  elseif has_key(a:item, 'menu')
    let l:parent_index = index(s:VisibleMenu(l:state.stack).items, a:item)
    if l:parent_index >= 0
      let l:state.selected[-1] = l:parent_index
    endif
    call add(l:state.stack, a:item.menu)
    call add(l:state.selected, empty(a:item.menu.items) ? 0 : 1)
    let l:state.mouse_pressed = -1
    let s:guides[string(a:id)] = l:state
    call popup_setoptions(a:id, {'firstline': 1})
    call s:RenderGuide(a:id)
    return
  endif

  let l:origin = l:state.origin
  let l:command = a:item.command
  call popup_close(a:id)
  if win_id2win(l:origin) > 0
    call win_gotoid(l:origin)
  endif
  " Queue the command so a Reload selection can safely source this file after
  " the popup filter and its script-local functions have returned.
  call feedkeys(':'.l:command."\<CR>", 'n')
endfunction

function! OnesimusGuideFilter(id, key) abort
  let l:state = get(s:guides, string(a:id), {})
  if empty(l:state)
    return 1
  endif
  let l:menu = s:VisibleMenu(l:state.stack)
  if index(["q", "\<Esc>", "\<C-C>"], a:key) >= 0
    call popup_close(a:id)
    return 1
  endif
  if index(["j", "\<Down>", "\<ScrollWheelDown>"], a:key) >= 0
    let l:count = len(l:menu.items)
    if l:count > 0
      let l:state.selected[-1] = (l:state.selected[-1] + 1) % l:count
      let s:guides[string(a:id)] = l:state
      call s:RenderGuide(a:id)
    endif
    return 1
  elseif index(["k", "\<Up>", "\<ScrollWheelUp>"], a:key) >= 0
    let l:count = len(l:menu.items)
    if l:count > 0
      let l:state.selected[-1] = (l:state.selected[-1] - 1 + l:count) % l:count
      let s:guides[string(a:id)] = l:state
      call s:RenderGuide(a:id)
    endif
    return 1
  elseif index(["\<CR>", " "], a:key) >= 0
    let l:index = get(l:state.selected, -1, 0)
    if l:index >= 0 && l:index < len(l:menu.items)
      call s:RunGuideItem(a:id, l:menu.items[l:index])
    endif
    return 1
  elseif a:key ==# "\<LeftMouse>"
    let l:index = s:MouseItemIndex(a:id, l:state)
    if l:index < 0
      if exists('*getmousepos') && get(getmousepos(), 'winid', 0) != a:id
        call popup_close(a:id)
      endif
    else
      " A press selects; only a release on the same row activates.  This
      " prevents the start of a touch swipe from launching an action.
      let l:state.selected[-1] = l:index
      let l:state.mouse_pressed = l:index
      let s:guides[string(a:id)] = l:state
      call s:RenderGuide(a:id)
    endif
    return 1
  elseif a:key ==# "\<LeftDrag>"
    let l:index = s:MouseItemIndex(a:id, l:state)
    if l:index >= 0
      let l:state.selected[-1] = l:index
    endif
    let l:state.mouse_pressed = -1
    let s:guides[string(a:id)] = l:state
    call s:RenderGuide(a:id)
    return 1
  elseif a:key ==# "\<LeftRelease>"
    let l:index = s:MouseItemIndex(a:id, l:state)
    let l:pressed = get(l:state, 'mouse_pressed', -1)
    let l:state.mouse_pressed = -1
    let s:guides[string(a:id)] = l:state
    if l:index >= 0 && l:index == l:pressed
      call s:RunGuideItem(a:id, l:menu.items[l:index])
    endif
    return 1
  endif
  if index(["\<BS>", "\<C-H>", "\<Left>"], a:key) >= 0
    call s:GuideBack(a:id)
    return 1
  endif
  for l:item in l:menu.items
    if a:key ==# l:item.key
      call s:RunGuideItem(a:id, l:item)
      return 1
    endif
  endfor
  return 1
endfunction

function! s:FallbackGuide(menu) abort
  let l:stack = [a:menu]
  while !empty(l:stack)
    let l:menu = s:VisibleMenu(l:stack)
    redraw
    let l:lines = s:MenuLines(l:menu, len(l:stack))
    let l:lines[-1] = '  Shown key to open · Esc closes'
    echo join(l:lines, "\n")
    let l:key = getchar()
    let l:key = type(l:key) is v:t_number ? nr2char(l:key) : l:key
    " Clear the old-Vim multiline echo's hit-enter state before acting.
    redraw!
    echo ''
    if index(["q", "\<Esc>", "\<C-C>"], l:key) >= 0
      return
    elseif index(["<", "\<BS>", "\<C-H>", "\<Left>"], l:key) >= 0
      call remove(l:stack, -1)
      continue
    endif
    for l:item in l:menu.items
      if l:key !=# l:item.key
        continue
      endif
      if has_key(l:item, 'menu')
        call add(l:stack, l:item.menu)
        break
      endif
      call feedkeys(':'.l:item.command."\<CR>", 'n')
      return
    endfor
  endwhile
endfunction

function! OnesimusGuide(...) abort
  let l:scope = get(a:000, 0, 'global')
  if exists('*OnesimusCheckExternalChanges')
    call OnesimusCheckExternalChanges(0)
  endif
  let l:menu = l:scope ==# 'context' ? s:ContextMenu() : s:GlobalMenu()
  if exists('*OnesimusTrack')
    call OnesimusTrack('meta.whichkey')
  endif
  if !OnesimusPopupSupported()
    call s:FallbackGuide(l:menu)
    return -1
  endif

  if s:active_guide > 0
    silent! call popup_close(s:active_guide)
  endif
  let l:lines = s:MenuLines(l:menu, 1, 0)
  let l:borderchars = &encoding ==# 'utf-8'
        \ ? ['─', '│', '─', '│', '┌', '┐', '┘', '└']
        \ : ['-', '|', '-', '|', '+', '+', '+', '+']
  " Mouse reporting is leased only while the guide is open.  This permits a
  " tap when tmux/zellij forwards it without stealing terminal text selection
  " during ordinary editing.
  let l:original_mouse = &mouse
  let &mouse = 'a'
  try
    let l:id = popup_create(l:lines, {
          \ 'pos': 'center',
          \ 'minwidth': s:PopupWidth(l:lines),
          \ 'maxwidth': max([20, &columns - 8]),
          \ 'maxheight': max([6, &lines - 6]),
          \ 'padding': [0, 1, 0, 1],
          \ 'border': [1, 1, 1, 1],
          \ 'borderchars': l:borderchars,
          \ 'borderhighlight': ['Comment'],
          \ 'highlight': 'Pmenu',
          \ 'mapping': 0,
          \ 'filter': function('OnesimusGuideFilter'),
          \ 'callback': function('<SID>GuideClosed'),
          \ 'close': 'button',
          \ 'scrollbar': 1,
          \ 'wrap': 0,
          \ 'zindex': 220,
          \ })
  catch
    let &mouse = l:original_mouse
    throw v:exception
  endtry
  let s:guides[string(l:id)] = {
        \ 'origin': win_getid(), 'stack': [l:menu], 'selected': [0],
        \ 'mouse_pressed': -1, 'original_mouse': l:original_mouse}
  let s:active_guide = l:id
  return l:id
endfunction
