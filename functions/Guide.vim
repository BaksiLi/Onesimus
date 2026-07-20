" A small native action guide.  Onesimus command names are stable APIs; this
" popup is the human interface and deliberately shows only common workflows.

let s:guides = {}
let s:active_guide = -1

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

function! s:Item(key, label, command) abort
  return {'key': a:key, 'label': a:label, 'command': a:command}
endfunction

function! s:Group(key, label, title, items) abort
  return {
        \ 'key': a:key,
        \ 'label': a:label,
        \ 'menu': {'title': a:title, 'items': a:items},
        \ }
endfunction

function! s:InGitRepository() abort
  let l:start = empty(expand('%:p')) ? getcwd() : expand('%:p:h')
  return !empty(finddir('.git', l:start.';'))
        \ || !empty(findfile('.git', l:start.';'))
endfunction

function! s:FindItems() abort
  let l:items = [
        \ s:Item('f', 'Files', 'OnesimusClap files'),
        \ s:Item('b', 'Buffers', 'OnesimusClap buffers'),
        \ s:Item('/', 'Search project', 'OnesimusClap grep'),
        \ s:Item('r', 'Recent files', 'OnesimusClap history'),
        \ ]
  if s:InGitRepository()
    call insert(l:items, s:Item('g', 'Git files', 'OnesimusClap git_files'), 1)
  endif
  return l:items
endfunction

function! s:LSPNavigationItems() abort
  return [
        \ s:Item('d', 'Definition',
        \   "call OnesimusLSPNavigate('definition')"),
        \ s:Item('r', 'References',
        \   "call OnesimusLSPNavigate('references')"),
        \ s:Item('i', 'Implementation',
        \   "call OnesimusLSPNavigate('implementation')"),
        \ s:Item('t', 'Type definition',
        \   "call OnesimusLSPNavigate('type_definition')"),
        \ ]
endfunction

function! s:ContextItems() abort
  let l:items = []
  if &l:buftype !=# '' || empty(&l:filetype)
    return l:items
  endif
  let l:run_filetypes = [
        \ 'c', 'cpp', 'dot', 'go', 'haskell', 'html', 'java', 'markdown',
        \ 'python', 'ruby', 'rust', 'sh', 'tex', 'typescript', 'vim',
        \ ]
  let l:prose = index(get(g:, 'onesimus_prose_filetypes', []), &l:filetype) >= 0

  if index(l:run_filetypes, &l:filetype) >= 0 && exists(':CompileRun')
    let l:label = &l:filetype ==# 'markdown' ? 'Preview'
          \ : (&l:filetype ==# 'tex' ? 'Compile document'
          \ : (&l:filetype ==# 'haskell' ? 'Check code' : 'Run / compile'))
    call add(l:items, s:Item('r', l:label, 'CompileRun'))
  endif
  if s:Installed('ale') && exists(':OnesimusFormat')
        \ && (has_key(get(g:, 'ale_fixers', {}), &l:filetype)
        \   || has_key(get(g:, 'ale_fixers', {}), '*'))
    call add(l:items, s:Item('f', 'Format buffer', 'OnesimusFormat'))
  endif
  if s:Installed('ale') && exists(':OnesimusDiagnostics')
        \ && has_key(get(g:, 'ale_linters', {}), &l:filetype)
    call add(l:items, s:Item('d', 'Problems', 'OnesimusDiagnostics'))
  endif
  if s:Installed('vim-clap') && exists(':OnesimusBufferSymbols')
    call add(l:items, s:Item('s', 'Buffer symbols', 'OnesimusBufferSymbols'))
  endif
  if l:prose && exists(':WPModeToggle')
    call add(l:items, s:Item('w', 'Focus writing', 'WPModeToggle'))
  endif
  if get(b:, 'onesimus_lsp_ready', 0)
        \ && s:Installed('ale') && exists('*OnesimusLSPNavigate')
    call add(l:items, s:Group('g', 'Navigate symbol', 'GO TO',
          \ s:LSPNavigationItems()))
    call add(l:items, s:Item('n', 'Rename symbol', 'OnesimusRenameSymbol'))
    call add(l:items, s:Item('a', 'Code action', 'OnesimusCodeAction'))
  endif
  return l:items
endfunction

function! s:GitItems() abort
  return [
        \ s:Item('s', 'Status', 'Git'),
        \ s:Item('d', 'Diff', 'Gdiffsplit'),
        \ s:Item('b', 'Blame', 'Git blame'),
        \ s:Item('l', 'Log', 'Git log'),
        \ ]
endfunction

function! s:ViewItems() abort
  let l:items = [
        \ s:Item('r', 'Relative numbers', 'OnesimusToggleRelativeNumber'),
        \ s:Item('i', 'Indent guides', 'OnesimusIndentToggle'),
        \ s:Item('p', 'Parenthesis colours', 'OnesimusParenthesisToggle'),
        \ s:Item('b', 'Light / dark', 'ToggleBackground'),
        \ ]
  if index(get(g:, 'onesimus_prose_filetypes', []), &l:filetype) >= 0
    call add(l:items, s:Item('w', 'Focus writing', 'WPModeToggle'))
  endif
  return l:items
endfunction

function! s:SystemItems() abort
  let l:items = []
  if s:Installed('vim-startify')
    call add(l:items, s:Item('h', 'Home', 'OnesimusHome'))
  endif
  call extend(l:items, [
        \ s:Item('i', 'Tool status', 'OnesimusHealth'),
        \ s:Item('u', 'Update', 'OnesimusUpdate'),
        \ s:Item('s', 'Usage', 'OnesimusStats'),
        \ s:Item('c', 'Edit config', 'OnesimusEditConfig'),
        \ s:Item('r', 'Reload config', 'OnesimusReload'),
        \ ])
  return l:items
endfunction

function! s:GlobalMenu() abort
  let l:items = []
  if s:Installed('vim-clap')
    call add(l:items, s:Group('f', 'Find', 'FIND', s:FindItems()))
  endif
  let l:context = s:ContextItems()
  if !empty(l:context)
    call add(l:items, s:Group('c', 'Current buffer', 'CURRENT BUFFER', l:context))
  endif
  if s:Installed('vim-fugitive') && s:InGitRepository()
    call add(l:items, s:Group('g', 'Git', 'GIT', s:GitItems()))
  endif
  call extend(l:items, [
        \ s:Group('t', 'View', 'VIEW', s:ViewItems()),
        \ s:Group('o', 'Onesimus', 'ONESIMUS', s:SystemItems()),
        \ s:Item('?', 'Help', 'OnesimusHelp'),
        \ ])
  return {'title': 'ACTIONS', 'items': l:items}
endfunction

function! s:ContextMenu() abort
  let l:items = s:ContextItems()
  if empty(l:items)
    let l:items = [s:Item('i', 'Tool status', 'OnesimusHealth')]
  endif
  return {'title': 'CURRENT BUFFER', 'items': l:items}
endfunction

function! s:MenuLines(menu, depth) abort
  let l:lines = ['  '.a:menu.title, '']
  for l:item in a:menu.items
    call add(l:lines, printf('  %-2s  %s%s', l:item.key, l:item.label,
          \ has_key(l:item, 'menu') ? '  >' : ''))
  endfor
  call extend(l:lines, ['', a:depth > 1
        \ ? '  Backspace back  ·  Esc close'
        \ : '  Esc close'])
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
  return popup_notification(l:preview, {
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
endfunction

function! s:GuideClosed(id, result) abort
  if has_key(s:guides, string(a:id))
    call remove(s:guides, string(a:id))
  endif
  if s:active_guide == a:id
    let s:active_guide = -1
  endif
endfunction

function! s:RenderGuide(id) abort
  let l:state = get(s:guides, string(a:id), {})
  if empty(l:state)
    return
  endif
  let l:menu = l:state.stack[-1]
  call popup_settext(a:id, s:MenuLines(l:menu, len(l:state.stack)))
endfunction

function! s:RunGuideItem(id, item) abort
  let l:state = get(s:guides, string(a:id), {})
  if empty(l:state)
    return
  endif
  if has_key(a:item, 'menu')
    call add(l:state.stack, a:item.menu)
    let s:guides[string(a:id)] = l:state
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
  if index(["q", "\<Esc>", "\<C-C>"], a:key) >= 0
    call popup_close(a:id)
    return 1
  endif
  if index(["\<BS>", "\<C-H>"], a:key) >= 0
    if len(l:state.stack) > 1
      call remove(l:state.stack, -1)
      let s:guides[string(a:id)] = l:state
      call s:RenderGuide(a:id)
    else
      call popup_close(a:id)
    endif
    return 1
  endif
  for l:item in l:state.stack[-1].items
    if a:key ==# l:item.key
      call s:RunGuideItem(a:id, l:item)
      return 1
    endif
  endfor
  return 1
endfunction

function! s:FallbackGuide(menu) abort
  redraw
  echo join(s:MenuLines(a:menu, 1), "\n")
  let l:key = getchar()
  let l:key = type(l:key) is v:t_number ? nr2char(l:key) : l:key
  " Multi-line :echo marks the screen as scrolled on old Vim.  Clear that
  " state before returning so a fallback action never leaves a hit-enter
  " prompt behind.
  redraw!
  echo ''
  if l:key ==# "\<Esc>"
    return
  endif
  for l:item in a:menu.items
    if l:key ==# l:item.key
      if has_key(l:item, 'menu')
        call s:FallbackGuide(l:item.menu)
      else
        call feedkeys(':'.l:item.command."\<CR>", 'n')
      endif
      return
    endif
  endfor
endfunction

function! OnesimusGuide(...) abort
  let l:scope = get(a:000, 0, 'global')
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
  let l:lines = s:MenuLines(l:menu, 1)
  let l:borderchars = &encoding ==# 'utf-8'
        \ ? ['─', '│', '─', '│', '┌', '┐', '┘', '└']
        \ : ['-', '|', '-', '|', '+', '+', '+', '+']
  let l:id = popup_create(l:lines, {
        \ 'pos': 'center',
        \ 'minwidth': s:PopupWidth(l:lines),
        \ 'padding': [0, 1, 0, 1],
        \ 'border': [1, 1, 1, 1],
        \ 'borderchars': l:borderchars,
        \ 'borderhighlight': ['Comment'],
        \ 'highlight': 'Pmenu',
        \ 'mapping': 0,
        \ 'filter': function('OnesimusGuideFilter'),
        \ 'callback': function('<SID>GuideClosed'),
        \ 'close': 'click',
        \ 'zindex': 220,
        \ })
  let s:guides[string(l:id)] = {'origin': win_getid(), 'stack': [l:menu]}
  let s:active_guide = l:id
  return l:id
endfunction

command! OnesimusGuide call OnesimusGuide('global')
