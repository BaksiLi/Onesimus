" A small native action guide.  Onesimus command names are stable APIs; this
" popup is the human interface and deliberately shows only common workflows.

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

function! s:Item(key, label, command) abort
  return {'key': a:key, 'label': a:label, 'command': a:command}
endfunction

" Formulas render through texinsitu.vim when it is installed.
function! s:MathItems() abort
  return exists(':TexInsituToggle') == 2 ? [s:Item('m', texinsitu#enabled()
        \ ? 'Use raw formulas' : 'Use rendered formulas', 'TexInsituToggle')] : []
endfunction

function! s:Group(key, label, title, items, ...) abort
  return {
        \ 'key': a:key,
        \ 'label': a:label,
        \ 'menu': {'title': a:title, 'items': a:items,
        \   'summary': get(a:000, 0, '')},
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

function! s:SourceConflictItems(tex) abort
  let l:write = a:tex ? 'OnesimusTexWriteResolved' : 'OnesimusWriteResolved'
  let l:use_disk = a:tex ? 'OnesimusTexUseDisk' : 'OnesimusUseDisk'
  let l:compare = a:tex ? 'OnesimusTexCompareDisk' : 'OnesimusDiffDisk'
  if filereadable(expand('%:p'))
    let l:items = [
          \ s:Item('d', 'Compare local buffer with disk', l:compare),
          \ s:Item('u', 'Use disk version  [discard local]', l:use_disk),
          \ s:Item('x', 'Save reviewed buffer over disk', l:write),
          \ ]
  elseif getftype(expand('%:p')) ==# ''
    let l:items = [
          \ s:Item('x', 'Recreate deleted source from local buffer', l:write),
          \ ]
  else
    let l:items = [
          \ s:Item('r', 'Re-check unreadable disk path', 'OnesimusCheckDisk'),
          \ ]
  endif
  if a:tex && exists('*OnesimusTexBuildRunning')
        \ && OnesimusTexBuildRunning()
    call insert(l:items,
          \ s:Item('l', 'Stop current build', 'OnesimusTexLiveBuild'), 1)
  endif
  if a:tex
    call add(l:items,
          \ s:Item('i', 'Workflow / project status', 'OnesimusTexStatus'))
  endif
  call add(l:items,
        \ s:Item('?', 'Conflict & collaboration guide',
        \   a:tex ? 'OnesimusTexHelp' : 'OnesimusWritingHelp'))
  return l:items
endfunction

function! s:FocusItem(key) abort
  let l:active = exists('*OnesimusWritingFocusActive')
        \ && OnesimusWritingFocusActive()
  return s:Item(a:key, l:active ? 'Leave focus mode' : 'Enter focus mode',
        \ 'WPModeToggle')
endfunction

function! s:SpellingGroup() abort
  return s:Group('e', 'Spelling', 'SPELLING', [
        \ s:Item('s', &l:spell ? 'Hide spelling marks' : 'Show spelling marks',
        \   'OnesimusWritingToggleSpell'),
        \ s:Item('n', 'Next spelling issue', 'OnesimusWritingNextSpelling'),
        \ s:Item('r', 'Suggestions at cursor', 'OnesimusWritingSuggest'),
        \ ], 'Dictionary: '.&l:spelllang)
endfunction

function! s:TeXMenu() abort
  let l:live = exists('*OnesimusTexBuildRunning')
        \ && OnesimusTexBuildRunning()
  let l:live_available = exists('*OnesimusTexLiveAvailable')
        \ && OnesimusTexLiveAvailable()
  let l:conflict = exists('*OnesimusHasExternalConflict')
        \ && OnesimusHasExternalConflict()
  if l:conflict
    return {'title': 'TEX PAPER · DISK CONFLICT',
          \ 'summary': 'Compare before choosing a version.',
          \ 'items': s:SourceConflictItems(1)}
  endif
  let l:tools = [
        \ s:Item('b', 'Save & build without opening', 'OnesimusTexBuild'),
        \ s:Item('v', 'Inspect final PDF externally', 'OnesimusTexOpenExternal'),
        \ s:Item('p', 'Preview session URL', 'OnesimusTexBrowser'),
        \ s:Item('k', get(g:, 'onesimus_tex_follow', 0) ? 'Stop PDF following cursor'
        \   : 'Browser PDF follows cursor', 'OnesimusTexFollow'),
        \ s:Item('c', 'Compiler log', 'OnesimusTexOutput'),
        \ s:Item('r', 'Check disk updates', 'OnesimusTexSync'),
        \ s:Item('d', 'Compare with disk', 'OnesimusTexCompareDisk'),
        \ s:Item('e', &l:spell ? 'Hide spelling marks' : 'Show spelling marks',
        \   'OnesimusWritingToggleSpell'),
        \ s:Item('i', 'Project & preview details', 'OnesimusTexStatus'),
        \ ]
  if l:live || l:live_available
    call insert(l:tools, s:Item('l', l:live ? 'Stop current build'
          \ : 'Save & start live build', 'OnesimusTexLiveBuild'))
  endif
  if s:Installed('ale') && exists(':OnesimusFormat')
    call add(l:tools, s:Item('f', 'Source indentation (F6)', 'OnesimusFormat'))
  endif
  if s:Installed('ale') && exists(':OnesimusDiagnostics')
    call add(l:tools, s:Item('a', 'TeX style warnings', 'OnesimusDiagnostics'))
  endif
  call extend(l:tools, [
        \ s:Item('x', 'Stop browser preview', 'OnesimusWritingPreviewStop'),
        \ s:Item('?', 'Writing help', 'OnesimusTexHelp')])
  return {'title': s:ContextTitle(), 'summary': OnesimusTexMenuSummary(),
        \ 'items': [
        \ s:Item('b', 'Save, build & preview (F5)', 'OnesimusTexPreview'),
        \ s:Item('v', 'Browser preview', 'OnesimusWritingPreview'),
        \ s:Item('d', 'Preview changes (latexdiff)', 'OnesimusDiff'),
        \ s:Item('s', 'Save text only', 'OnesimusTexSave'),
        \ s:Item('t', 'Outline / sections', 'OnesimusTexOutline'),
        \ s:Item('e', 'Compilation errors', 'OnesimusTexErrors'),
        \ ] + s:MathItems() + [
        \ s:FocusItem('z'),
        \ s:Item('n', 'Sentence lines (review)', 'OnesimusTexSentenceLines'),
        \ s:Item('w', 'Manuscript word count', 'OnesimusTexCountWords'),
        \ s:Group('o', 'More tools', 'TEX TOOLS', l:tools),
        \ ]}
endfunction

function! s:IsWritingBuffer() abort
  return OnesimusIsWritingBuffer(bufnr('%'))
endfunction

function! s:WritingMenu() abort
  let l:items = []
  if &l:filetype ==# 'markdown' || &l:filetype ==# 'cogitatum'
    call add(l:items, s:Item('v', 'Browser preview (F5)', 'OnesimusWritingPreview'))
  endif
  call add(l:items, s:Item('s', &l:filetype ==# 'bib'
        \ ? 'Save bibliography' : 'Save text', 'OnesimusWritingSave'))
  let l:tools = [
        \ s:Item('r', 'Check disk updates', 'OnesimusCheckDisk'),
        \ s:Item('d', 'Compare with disk', 'OnesimusDiffDisk')]
  if &l:filetype !=# 'bib'
    if index(['markdown', 'cogitatum'], &l:filetype) >= 0
      call extend(l:items, s:MathItems())
      call add(l:tools, s:Item('x', 'Stop browser preview', 'OnesimusWritingPreviewStop'))
    endif
    let l:inquiry = &l:filetype ==# 'cogitatum'
          \ || (&l:filetype ==# 'markdown'
          \   && search('^\s*\%(```\+\|[~]\{3,}\)\s*\%(cog\|cogitatum\)\s*$', 'nw') > 0)
    if l:inquiry && exists(':CogPreview') == 2
      if &l:filetype ==# 'markdown'
        call add(l:items, s:Item('i', 'Preview inquiry fences', 'WebPreviewInquiry'))
      endif
      call add(l:items, s:Item('r', 'Terminal Reading (saved file)', 'CogRead'))
      call add(l:tools, s:Item('m', 'Terminal Map (saved file)', 'CogMap'))
    endif
    if &l:filetype ==# 'cogitatum' && s:Installed('ale')
      call extend(l:items, [
            \ s:Item('t', 'Outline / names', 'OnesimusBufferSymbols'),
            \ s:Item('d', 'Inquiry problems', 'OnesimusDiagnostics'),
            \ s:Group('g', 'Navigate name', 'GO TO', s:LSPNavigationItems()),
            \ ])
    endif
    call extend(l:items, [s:FocusItem('z'),
          \ s:Item('w', 'Word count', 'OnesimusWritingCountWords'),
          \ s:SpellingGroup()])
  endif
  if s:Installed('ale') && exists(':OnesimusFormat')
    call add(l:tools, s:Item('f', 'Format text (F6)', 'OnesimusFormat'))
  endif
  if &l:filetype ==# 'bib'
    call extend(l:items, l:tools)
    call add(l:items, s:Item('?', 'Writing help', 'OnesimusWritingHelp'))
  else
    call add(l:tools, s:Item('?', 'Writing help', 'OnesimusWritingHelp'))
    call add(l:items, s:Group('o', 'More tools',
          \ 'WRITING TOOLS', l:tools, 'Reloading never saves.'))
  endif
  return {'title': s:ContextTitle(), 'items': l:items,
        \ 'summary': &l:modified ? 'Unsaved edits' : 'No unsaved edits'}
endfunction

function! s:ContextItems() abort
  let l:items = []
  if &l:buftype !=# '' || (empty(&l:filetype) && !s:IsWritingBuffer())
    return l:items
  endif
  if s:IsWritingBuffer() && exists('*OnesimusHasExternalConflict')
        \ && OnesimusHasExternalConflict()
    return s:SourceConflictItems(&l:filetype ==# 'tex')
  endif
  if &l:filetype ==# 'tex' && exists(':OnesimusTexStatus') == 2
    return s:TeXMenu().items
  endif
  if s:IsWritingBuffer()
    return s:WritingMenu().items
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

function! s:ContextTitle() abort
  if exists('*OnesimusHasExternalConflict') && OnesimusHasExternalConflict()
    return toupper(empty(&l:filetype) ? 'SOURCE' : &l:filetype)
          \ .' · DISK CONFLICT'
  endif
  let l:kind = &l:filetype ==# 'tex' ? 'TEX PAPER'
        \ : (&l:filetype ==# 'bib' ? 'BIBLIOGRAPHY'
        \ : (&l:filetype ==# 'markdown' ? 'MARKDOWN WRITING'
        \ : (&l:filetype ==# 'cogitatum' ? 'COGITATUM INQUIRY'
        \ : (s:IsWritingBuffer() ? 'WRITING' : 'CURRENT BUFFER'))))
  return l:kind.(empty(bufname('%')) ? '' : ' · '.expand('%:t'))
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
        \ s:Item('d', 'Redraw terminal display  [Ctrl-L]', 'OnesimusRedraw'),
        \ ]
  if index(get(g:, 'onesimus_prose_filetypes', []), &l:filetype) >= 0
    call add(l:items, s:FocusItem('w'))
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
  if !empty(s:ContextItems())
    let l:label = &l:filetype ==# 'tex' ? 'TeX paper'
          \ : (&l:filetype ==# 'bib' ? 'Bibliography'
          \ : (s:IsWritingBuffer() ? 'Writing' : 'Current buffer'))
    call insert(l:items, {'key': '\', 'label': 'Current file · '.l:label,
          \ 'menu': s:ContextMenu()})
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
  if &l:buftype ==# '' && &l:filetype ==# 'tex'
        \ && exists(':OnesimusTexStatus') == 2
    return s:TeXMenu()
  endif
  if s:IsWritingBuffer() && !(exists('*OnesimusHasExternalConflict')
        \ && OnesimusHasExternalConflict())
    return s:WritingMenu()
  endif
  let l:items = s:ContextItems()
  if empty(l:items)
    let l:items = [s:Item('i', 'Tool status', 'OnesimusHealth')]
  endif
  return {'title': s:ContextTitle(), 'items': l:items}
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

command! OnesimusGuide call OnesimusGuide()
