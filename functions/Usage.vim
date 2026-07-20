" Local feature-adoption journal and dashboard for Onesimus.
"
" This deliberately records only stable Onesimus action IDs, eligible
" features, and coarse filetypes.  It never records paths, buffer contents,
" search queries, command text, hostnames, or anything over the network.

let g:onesimus_usage_enabled = get(g:, 'onesimus_usage_enabled', 1)

let s:catalog = [
      \ {'id': 'meta.home', 'label': 'Open home', 'group': 'Onesimus', 'key': '<Leader>oh', 'kind': 'explicit'},
      \ {'id': 'meta.help', 'label': 'Read documentation', 'group': 'Onesimus', 'key': '<Leader>h', 'kind': 'explicit'},
      \ {'id': 'meta.config', 'label': 'Edit configuration', 'group': 'Onesimus', 'key': '<Leader>ed', 'kind': 'explicit'},
      \ {'id': 'meta.reload', 'label': 'Reload configuration', 'group': 'Onesimus', 'key': '<Leader>sd', 'kind': 'explicit'},
      \ {'id': 'meta.update', 'label': 'Update Onesimus', 'group': 'Onesimus', 'key': '<Leader> o u', 'kind': 'explicit'},
      \ {'id': 'meta.stats', 'label': 'Usage dashboard', 'group': 'Onesimus', 'key': '<Leader>os', 'kind': 'explicit'},
      \ {'id': 'meta.whichkey', 'label': 'Open action guide', 'group': 'Onesimus', 'key': '<Leader>', 'kind': 'explicit', 'tip': 'Pause after <Leader> for a short action guide; <Leader>. adapts to this buffer.'},
      \ {'id': 'find.files', 'label': 'Find files', 'group': 'Find', 'key': '<Leader>ff', 'kind': 'explicit', 'tip': '<Leader>ff finds files without leaving Vim.'},
      \ {'id': 'find.git_files', 'label': 'Find Git files', 'group': 'Find', 'key': '<Leader>fg', 'kind': 'explicit'},
      \ {'id': 'find.buffers', 'label': 'Find buffers', 'group': 'Find', 'key': '<Leader>fb', 'kind': 'explicit'},
      \ {'id': 'find.grep', 'label': 'Search project text', 'group': 'Find', 'key': '<Leader>fw', 'kind': 'explicit', 'tip': '<Leader>fw searches project text through Clap.'},
      \ {'id': 'find.tags', 'label': 'Find buffer tags', 'group': 'Find', 'key': '<Leader>ft', 'kind': 'explicit'},
      \ {'id': 'find.marks', 'label': 'Find marks', 'group': 'Find', 'key': '<Leader>fm', 'kind': 'explicit'},
      \ {'id': 'find.history', 'label': 'Recent files', 'group': 'Find', 'key': '<Leader>fh', 'kind': 'explicit'},
      \ {'id': 'find.command_history', 'label': 'Command history', 'group': 'Find', 'key': '<Leader>fc', 'kind': 'explicit'},
      \ {'id': 'nav.tree', 'label': 'File tree', 'group': 'Navigate', 'key': 'F3', 'kind': 'explicit', 'tip': 'F3 toggles the file tree.'},
      \ {'id': 'nav.buffer_symbols', 'label': 'Buffer symbols', 'group': 'Navigate', 'key': 'F2 / gs', 'kind': 'explicit', 'tip': 'gs lists symbols in the current buffer.'},
      \ {'id': 'nav.workspace_symbols', 'label': 'Workspace symbols', 'group': 'Navigate', 'key': 'gS', 'kind': 'explicit'},
      \ {'id': 'nav.tags', 'label': 'Build project tags', 'group': 'Navigate', 'key': '<Leader>et', 'kind': 'explicit'},
      \ {'id': 'code.run', 'label': 'Compile or run', 'group': 'Code', 'key': 'F5', 'kind': 'explicit', 'tip': 'F5 runs the current file with its language tool.'},
      \ {'id': 'code.format', 'label': 'Format buffer', 'group': 'Code', 'key': 'F6', 'kind': 'explicit', 'tip': 'F6 formats explicitly; saving never rewrites code.'},
      \ {'id': 'code.diagnostics', 'label': 'Open diagnostics', 'group': 'Code', 'key': '<Leader>ld', 'kind': 'explicit'},
      \ {'id': 'code.health', 'label': 'Check tool health', 'group': 'Code', 'key': '<Leader>li', 'kind': 'explicit', 'tip': '<Leader>li explains the active language tools.'},
      \ {'id': 'code.definition', 'label': 'Go to definition', 'group': 'Code', 'key': 'gd', 'kind': 'explicit'},
      \ {'id': 'code.references', 'label': 'Find references', 'group': 'Code', 'key': 'gr', 'kind': 'explicit'},
      \ {'id': 'code.implementation', 'label': 'Go to implementation', 'group': 'Code', 'key': '<Leader>. g i', 'kind': 'explicit'},
      \ {'id': 'code.type_definition', 'label': 'Go to type', 'group': 'Code', 'key': '<Leader>. g t', 'kind': 'explicit'},
      \ {'id': 'code.hover', 'label': 'Hover documentation', 'group': 'Code', 'key': 'K', 'kind': 'explicit'},
      \ {'id': 'code.rename', 'label': 'Rename symbol', 'group': 'Code', 'key': '<Leader>rn', 'kind': 'explicit'},
      \ {'id': 'code.action', 'label': 'Code action', 'group': 'Code', 'key': '<Leader>ca', 'kind': 'explicit'},
      \ {'id': 'repl.open', 'label': 'Open REPL', 'group': 'Code', 'key': 'F4', 'kind': 'explicit'},
      \ {'id': 'writing.focus', 'label': 'Focus writing mode', 'group': 'Write', 'key': '<Leader>tw', 'kind': 'explicit', 'tip': '<Leader>tw enters a distraction-free writing view.'},
      \ {'id': 'writing.cjk', 'label': 'CJK segmentation active', 'group': 'Write', 'key': 'w / iw', 'kind': 'passive'},
      \ {'id': 'ui.relative_number', 'label': 'Relative numbers', 'group': 'Interface', 'key': '<Leader>tr', 'kind': 'explicit'},
      \ {'id': 'ui.indent_guides', 'label': 'Indent guides', 'group': 'Interface', 'key': '<Leader>ti', 'kind': 'explicit'},
      \ {'id': 'ui.parentheses', 'label': 'Parenthesis colours', 'group': 'Interface', 'key': '<Leader>tp', 'kind': 'explicit'},
      \ {'id': 'ui.background', 'label': 'Light/dark background', 'group': 'Interface', 'key': '<Leader>tb', 'kind': 'explicit'},
      \ {'id': 'theme.gruvbox', 'label': 'Theme: gruvbox', 'group': 'Themes', 'key': '', 'kind': 'passive'},
      \ {'id': 'theme.nord', 'label': 'Theme: nord', 'group': 'Themes', 'key': '', 'kind': 'passive'},
      \ {'id': 'theme.seoul256', 'label': 'Theme: seoul256', 'group': 'Themes', 'key': '', 'kind': 'passive'},
      \ {'id': 'theme.monokai', 'label': 'Theme: monokai', 'group': 'Themes', 'key': '', 'kind': 'passive'},
      \ ]

let s:catalog_by_id = {}
for s:item in s:catalog
  let s:catalog_by_id[s:item.id] = s:item
endfor
unlet! s:item

let s:filetypes = {
      \ 'applescript': 1, 'c': 1, 'cpp': 1, 'dot': 1, 'gitcommit': 1,
      \ 'go': 1, 'haskell': 1, 'help': 1, 'html': 1, 'java': 1,
      \ 'javascript': 1, 'javascriptreact': 1, 'json': 1, 'lisp': 1,
      \ 'markdown': 1, 'python': 1, 'ruby': 1, 'rust': 1, 'scheme': 1,
      \ 'sh': 1, 'snippets': 1, 'swift': 1, 'tex': 1, 'text': 1,
      \ 'typescript': 1, 'typescriptreact': 1, 'vim': 1, 'yaml': 1,
      \ }
let s:run_filetypes = {
      \ 'c': 1, 'cpp': 1, 'dot': 1, 'go': 1, 'haskell': 1, 'html': 1,
      \ 'java': 1, 'markdown': 1, 'python': 1, 'ruby': 1, 'rust': 1,
      \ 'sh': 1, 'tex': 1, 'typescript': 1, 'vim': 1,
      \ }
let s:repl_filetypes = {
      \ 'haskell': 1, 'python': 1, 'ruby': 1, 'scheme': 1, 'vim': 1,
      \ }

function! s:NewRuntime() abort
  return {
        \ 'started_at': localtime(),
        \ 'updated_at': localtime(),
        \ 'counts': {},
        \ 'last': {},
        \ 'eligible': {},
        \ 'filetypes': {},
        \ 'once': {},
        \ 'dirty': 1,
        \ 'file': '',
        \ 'last_error': '',
        \ }
endfunction

if !exists('g:onesimus_usage_runtime')
  let g:onesimus_usage_runtime = s:NewRuntime()
elseif !has_key(g:onesimus_usage_runtime, 'last')
  " In-process migration for :OnesimusReload from the first journal format.
  let g:onesimus_usage_runtime.last = {}
endif
let s:runtime = g:onesimus_usage_runtime

function! s:StateRoot() abort
  if exists('g:onesimus_usage_state_dir')
    let l:override = fnamemodify(g:onesimus_usage_state_dir, ':p')
    if !empty(l:override)
      return l:override
    endif
  endif

  if !empty($XDG_STATE_HOME)
    let l:base = $XDG_STATE_HOME
  elseif has('win32') || has('win64')
    let l:base = !empty($LOCALAPPDATA) ? $LOCALAPPDATA : expand('~/vimfiles')
  else
    let l:base = expand('~/.local/state')
  endif
  return fnamemodify(l:base.'/onesimus/usage/v1', ':p')
endfunction

function! s:SessionPath() abort
  if !empty(s:runtime.file)
    return s:runtime.file
  endif

  let l:month = strftime('%Y-%m', s:runtime.started_at)
  let l:name = printf('%s-%d.json',
        \ strftime('%Y%m%d-%H%M%S', s:runtime.started_at), getpid())
  let s:runtime.file = s:StateRoot().'/'.l:month.'/'.l:name
  return s:runtime.file
endfunction

function! OnesimusUsageCatalog() abort
  return deepcopy(s:catalog)
endfunction

function! OnesimusTrack(action) abort
  if !get(g:, 'onesimus_usage_enabled', 1)
        \ || !has_key(s:catalog_by_id, a:action)
    return 0
  endif

  let s:runtime.counts[a:action] = get(s:runtime.counts, a:action, 0) + 1
  let s:runtime.last[a:action] = localtime()
  let s:runtime.eligible[a:action] = 1
  let s:runtime.once[a:action] = 1
  let s:runtime.updated_at = localtime()
  let s:runtime.dirty = 1
  return 1
endfunction

function! OnesimusTrackOnce(action) abort
  if has_key(s:runtime.once, a:action)
    return 0
  endif
  return OnesimusTrack(a:action)
endfunction

function! OnesimusOffer(action) abort
  if !get(g:, 'onesimus_usage_enabled', 1)
        \ || !has_key(s:catalog_by_id, a:action)
    return 0
  endif
  let s:runtime.eligible[a:action] = 1
  let s:runtime.dirty = 1
  return 1
endfunction

" Record availability separately from use.  A zero is useful as removal
" evidence only after the action was genuinely available in enough sessions.
function! s:PluginInstalled(name) abort
  return exists('*PlugInstalled') && PlugInstalled(a:name)
endfunction

function! s:OfferSessionFeatures() abort
  for l:id in ['meta.help', 'meta.config', 'meta.reload', 'meta.update', 'meta.stats',
        \ 'code.health', 'ui.relative_number',
        \ 'ui.indent_guides', 'ui.parentheses', 'ui.background']
    call OnesimusOffer(l:id)
  endfor

  if s:PluginInstalled('vim-startify')
    call OnesimusOffer('meta.home')
  endif
  call OnesimusOffer('meta.whichkey')
  if s:PluginInstalled('vim-clap')
    for l:id in ['find.files', 'find.git_files', 'find.buffers', 'find.grep',
          \ 'find.tags', 'find.marks', 'find.history',
          \ 'find.command_history', 'nav.buffer_symbols']
      call OnesimusOffer(l:id)
    endfor
  endif
  if s:PluginInstalled('nerdtree')
    call OnesimusOffer('nav.tree')
  endif
  if executable('ctags')
    call OnesimusOffer('nav.tags')
  endif
endfunction

function! OnesimusObserveFiletype(filetype) abort
  if !get(g:, 'onesimus_usage_enabled', 1) || empty(a:filetype)
    return
  endif

  let l:filetype = has_key(s:filetypes, a:filetype) ? a:filetype : 'other'
  let s:runtime.filetypes[l:filetype] = 1
  let s:runtime.dirty = 1

  if has_key(s:run_filetypes, a:filetype)
    call OnesimusOffer('code.run')
  endif
  if has_key(s:repl_filetypes, a:filetype)
    call OnesimusOffer('repl.open')
  endif
  if has_key(get(g:, 'ale_fixers', {}), a:filetype)
    call OnesimusOffer('code.format')
  endif
  if has_key(get(g:, 'ale_linters', {}), a:filetype)
    call OnesimusOffer('code.diagnostics')
    call OnesimusOffer('code.health')
  endif
  if index(get(g:, 'onesimus_prose_filetypes', []), a:filetype) >= 0
    call OnesimusOffer('writing.focus')
  endif
endfunction

function! s:CurrentRecord() abort
  return {
        \ 'v': 1,
        \ 'started_at': s:runtime.started_at,
        \ 'updated_at': s:runtime.updated_at,
        \ 'vim': printf('%d.%d', v:version / 100, v:version % 100),
        \ 'onesimus': get(g:, 'onesimus_version', 'dev'),
        \ 'counts': copy(s:runtime.counts),
        \ 'last': copy(s:runtime.last),
        \ 'eligible': copy(s:runtime.eligible),
        \ 'filetypes': copy(s:runtime.filetypes),
        \ }
endfunction

function! OnesimusUsageFlush() abort
  if !get(g:, 'onesimus_usage_enabled', 1) || !get(s:runtime, 'dirty', 0)
    return 1
  endif

  let l:path = s:SessionPath()
  let l:tmp = l:path.'.tmp'
  try
    call mkdir(fnamemodify(l:path, ':h'), 'p', 0700)
    call writefile([json_encode(s:CurrentRecord())], l:tmp, 'b')
    if exists('*setfperm')
      silent! call setfperm(l:tmp, 'rw-------')
    endif
    if rename(l:tmp, l:path) != 0
      throw 'could not replace '.l:path
    endif
    let s:runtime.dirty = 0
    let s:runtime.last_error = ''
    return 1
  catch
    let s:runtime.last_error = v:exception
    silent! call delete(l:tmp)
    return 0
  endtry
endfunction

function! s:ValidRecord(record) abort
  return type(a:record) is v:t_dict
        \ && get(a:record, 'v', 0) == 1
        \ && type(get(a:record, 'started_at', 0)) is v:t_number
        \ && (!has_key(a:record, 'updated_at')
        \   || type(a:record.updated_at) is v:t_number)
        \ && type(get(a:record, 'counts', 0)) is v:t_dict
        \ && (!has_key(a:record, 'last')
        \   || type(a:record.last) is v:t_dict)
        \ && type(get(a:record, 'eligible', 0)) is v:t_dict
        \ && type(get(a:record, 'filetypes', 0)) is v:t_dict
endfunction

function! s:Records(days) abort
  let l:cutoff = localtime() - (a:days * 86400)
  let l:current = fnamemodify(s:SessionPath(), ':p')
  let l:records = []
  let l:months = {}
  for l:offset in range(0, a:days)
    let l:months[strftime('%Y-%m', localtime() - (l:offset * 86400))] = 1
  endfor

  for l:month in keys(l:months)
    for l:file in globpath(s:StateRoot(), l:month.'/*.json', 0, 1)
      if fnamemodify(l:file, ':p') ==# l:current
            \ || getftime(l:file) < l:cutoff
        continue
      endif
      try
        let l:record = json_decode(join(readfile(l:file, '', 2), ''))
        if s:ValidRecord(l:record)
              \ && get(l:record, 'started_at', 0) >= l:cutoff
          call add(l:records, l:record)
        endif
      catch
        " A truncated or old journal must never break Vim or the dashboard.
      endtry
    endfor
  endfor

  if s:runtime.started_at >= l:cutoff
    call add(l:records, s:CurrentRecord())
  endif
  return l:records
endfunction

function! s:Aggregate(days) abort
  let l:result = {
        \ 'days': a:days, 'sessions': 0, 'active_days': 0,
        \ 'action_count': 0, 'actions': {}, 'filetypes': {}, 'daily': {},
        \ 'oldest': localtime(),
        \ }
  let l:active_days = {}

  for l:record in s:Records(a:days)
    let l:result.sessions += 1
    let l:started = get(l:record, 'started_at', localtime())
    if type(l:started) isnot v:t_number
      let l:started = localtime()
    endif
    let l:result.oldest = min([l:result.oldest, l:started])
    let l:day = strftime('%Y-%m-%d', l:started)
    let l:active_days[l:day] = 1
    let l:daily_count = 0

    for [l:id, l:count] in items(get(l:record, 'counts', {}))
      if !has_key(s:catalog_by_id, l:id) || type(l:count) isnot v:t_number
        continue
      endif
      let l:entry = get(l:result.actions, l:id,
            \ {'count': 0, 'sessions': 0, 'eligible': 0, 'last': 0})
      let l:entry.count += l:count
      let l:entry.sessions += l:count > 0 ? 1 : 0
      let l:last = get(get(l:record, 'last', {}), l:id,
            \ get(l:record, 'updated_at', l:started))
      if type(l:last) isnot v:t_number
        let l:last = get(l:record, 'updated_at', l:started)
      endif
      if type(l:last) isnot v:t_number
        let l:last = l:started
      endif
      let l:entry.last = max([l:entry.last, l:last])
      let l:result.actions[l:id] = l:entry
      let l:result.action_count += l:count
      let l:daily_count += l:count
    endfor

    for l:id in keys(get(l:record, 'eligible', {}))
      if !has_key(s:catalog_by_id, l:id)
        continue
      endif
      let l:entry = get(l:result.actions, l:id,
            \ {'count': 0, 'sessions': 0, 'eligible': 0, 'last': 0})
      let l:entry.eligible += 1
      let l:result.actions[l:id] = l:entry
    endfor

    for l:filetype in keys(get(l:record, 'filetypes', {}))
      let l:result.filetypes[l:filetype] =
            \ get(l:result.filetypes, l:filetype, 0) + 1
    endfor
    let l:result.daily[l:day] = get(l:result.daily, l:day, 0) + l:daily_count
  endfor

  let l:result.active_days = len(l:active_days)
  let l:result.age_days = l:result.sessions == 0 ? 0
        \ : ((localtime() - l:result.oldest) / 86400) + 1
  return l:result
endfunction

function! s:Sparkline(daily, days) abort
  let l:values = []
  for l:offset in reverse(range(0, a:days - 1))
    let l:day = strftime('%Y-%m-%d', localtime() - (l:offset * 86400))
    call add(l:values, get(a:daily, l:day, 0))
  endfor

  let l:bins = a:days <= 14 ? a:days : (a:days <= 30 ? 15 : 18)
  let l:binned = repeat([0], l:bins)
  for l:index in range(0, len(l:values) - 1)
    let l:bucket = min([l:bins - 1, (l:index * l:bins) / len(l:values)])
    let l:binned[l:bucket] += l:values[l:index]
  endfor

  let l:maximum = max(l:binned)
  let l:glyphs = split('▁▂▃▄▅▆▇█', '\zs')
  let l:spark = ''
  for l:value in l:binned
    let l:spark .= l:value == 0 ? '·'
          \ : l:glyphs[((l:value - 1) * (len(l:glyphs) - 1)) / max([1, l:maximum])]
  endfor
  return l:spark
endfunction

function! OnesimusUsageSummary(...) abort
  let l:days = get(a:000, 0, 7)
  let l:summary = s:Aggregate(l:days)
  let l:summary.sparkline = s:Sparkline(l:summary.daily, l:days)
  return l:summary
endfunction

function! s:DiscoveryTip(summary) abort
  let l:candidates = []
  let l:minimum = 0x7fffffff
  for l:item in s:catalog
    if !has_key(l:item, 'tip')
          \ || !has_key(s:runtime.eligible, l:item.id)
      continue
    endif
    let l:used = get(get(a:summary.actions, l:item.id, {}), 'sessions', 0)
    if l:used < l:minimum
      let l:minimum = l:used
      let l:candidates = [l:item]
    elseif l:used == l:minimum
      call add(l:candidates, l:item)
    endif
  endfor
  if empty(l:candidates)
    return 'Press <Leader> and pause; the guide shows what is available.'
  endif
  let l:index = (localtime() / 86400 + a:summary.sessions) % len(l:candidates)
  return l:candidates[l:index].tip
endfunction

function! OnesimusHomeHeader() abort
  let l:cwd = pathshorten(fnamemodify(getcwd(), ':~'))
  return [
        \ '  ONESIMUS',
        \ printf('  Vim, made helpful · Vim %d.%d',
        \   v:version / 100, v:version % 100),
        \ '  '.l:cwd,
        \ ]
endfunction

function! OnesimusHomeActions() abort
  for l:id in ['meta.whichkey', 'meta.update', 'code.health']
    call OnesimusOffer(l:id)
  endfor
  if s:PluginInstalled('vim-clap')
    call OnesimusOffer('find.files')
    call OnesimusOffer('find.grep')
  endif
  return [
        \ {'line': 'Files', 'cmd': 'OnesimusClap files'},
        \ {'line': 'Search project', 'cmd': 'OnesimusClap grep'},
        \ {'line': 'Action guide', 'cmd': 'OnesimusGuide'},
        \ {'line': 'Tool status', 'cmd': 'OnesimusHealth'},
        \ {'line': 'Update Onesimus', 'cmd': 'OnesimusUpdate'},
        \ ]
endfunction

function! OnesimusHomeFooter() abort
  let l:summary = OnesimusUsageSummary(7)
  let l:activity = l:summary.action_count == 0
        \ ? 'learning starts locally today'
        \ : printf('%d actions · %d active days',
        \     l:summary.action_count, l:summary.active_days)
  return [
        \ '',
        \ printf('  7 days  %s  %s', l:summary.sparkline, l:activity),
        \ '  Guide   pause after \ anywhere · \. for this buffer',
        \ '  Try     '.s:DiscoveryTip(l:summary),
        \ '  Local only · no filenames, content, or network · \os for usage',
        \ ]
endfunction

function! s:CompareEntries(left, right) abort
  if a:left.count == a:right.count
    return a:left.label ==# a:right.label ? 0
          \ : (a:left.label ># a:right.label ? 1 : -1)
  endif
  return a:right.count - a:left.count
endfunction

function! s:CompareFiletypes(left, right) abort
  return a:left[1] == a:right[1] ? 0 : a:right[1] - a:left[1]
endfunction

function! s:StatsLines(days) abort
  let l:summary = OnesimusUsageSummary(a:days)
  let l:entries = []
  for l:item in s:catalog
    let l:usage = get(l:summary.actions, l:item.id,
          \ {'count': 0, 'sessions': 0, 'eligible': 0, 'last': 0})
    call add(l:entries, extend(copy(l:item), l:usage))
  endfor
  call sort(l:entries, function('<SID>CompareEntries'))

  let l:used = filter(copy(l:entries), 'v:val.count > 0')
  let l:maximum = empty(l:used) ? 1 : l:used[0].count
  let l:bar_width = max([8, min([24, winwidth(0) - 62])])
  let l:lines = [
        \ 'ONESIMUS / LOCAL USAGE',
        \ '',
        \ printf('  Last %d days · %d sessions · %d active days · %d actions',
        \   a:days, l:summary.sessions, l:summary.active_days,
        \   l:summary.action_count),
        \ '  '.l:summary.sparkline,
        \ '',
        \ '  FEATURE ADOPTION',
        \ ]

  if empty(l:used)
    call add(l:lines, '  No explicit actions recorded yet. Use Vim normally.')
  else
    for l:entry in l:used[:14]
      let l:filled = max([1, (l:entry.count * l:bar_width) / l:maximum])
      let l:bar = &encoding ==# 'utf-8'
            \ ? repeat('█', l:filled).repeat('░', l:bar_width - l:filled)
            \ : repeat('#', l:filled).repeat('.', l:bar_width - l:filled)
      let l:last = l:entry.last > 0 ? strftime('%m-%d', l:entry.last) : '—'
      call add(l:lines, printf('  %-22s %s %4d  %2d/%-2d sessions  %s',
            \ l:entry.label, l:bar, l:entry.count, l:entry.sessions,
            \ l:entry.eligible, l:last))
    endfor
  endif

  let l:filetypes = items(l:summary.filetypes)
  call sort(l:filetypes, function('<SID>CompareFiletypes'))
  call extend(l:lines, ['', '  FILETYPE SESSIONS'])
  if empty(l:filetypes)
    call add(l:lines, '  No filetypes observed yet.')
  else
    let l:parts = []
    for l:item in l:filetypes[:11]
      call add(l:parts, printf('%s %d', l:item[0], l:item[1]))
    endfor
    call add(l:lines, '  '.join(l:parts, '  ·  '))
  endif

  let l:untried = filter(copy(l:entries),
        \ 'v:val.kind ==# "explicit" && v:val.count == 0 && v:val.eligible > 0')
  call extend(l:lines, ['', '  UNTRIED, BUT AVAILABLE'])
  if empty(l:untried)
    call add(l:lines, '  Nothing currently qualifies.')
  else
    call add(l:lines, '  '.join(map(l:untried[:9],
          \ 'v:val.label." (".v:val.eligible." sessions)"'), '  ·  '))
  endif

  let l:cold = filter(copy(l:entries),
        \ 'v:val.kind ==# "explicit" && v:val.sessions == 0 && '
        \ .'v:val.eligible >= 10 && l:summary.age_days >= 30')
  call extend(l:lines, ['', '  COLD CANDIDATES'])
  if empty(l:cold)
    call add(l:lines, printf(
          \ '  Needs at least 30 days and 10 eligible sessions; currently day %d.',
          \ l:summary.age_days))
  else
    call add(l:lines, '  '.join(map(l:cold, 'v:val.label'), '  ·  '))
  endif

  call extend(l:lines, [
        \ '',
        \ '  7 / 3 / 9  change window    r  refresh    q  close',
        \ '  Local session journals only. No paths, content, queries, or network.',
        \ '  Data: '.s:StateRoot(),
        \ ])
  if !empty(get(s:runtime, 'last_error', ''))
    call add(l:lines, '  Write warning: '.s:runtime.last_error)
  endif
  return l:lines
endfunction

function! s:RenderStats(days) abort
  let b:onesimus_stats_days = a:days
  setlocal modifiable
  silent %delete _
  call setline(1, s:StatsLines(a:days))
  setlocal nomodifiable nomodified
  normal! gg
endfunction

function! s:FindStatsBuffer() abort
  for l:buffer in getbufinfo()
    if getbufvar(l:buffer.bufnr, 'onesimus_stats_buffer', 0)
      return l:buffer.bufnr
    endif
  endfor
  return -1
endfunction

function! s:OpenStats(days) abort
  call OnesimusTrack('meta.stats')
  let l:buffer = s:FindStatsBuffer()
  if l:buffer > 0
    let l:window = bufwinnr(l:buffer)
    if l:window > 0
      execute l:window.'wincmd w'
    else
      execute 'botright sbuffer '.l:buffer
    endif
    call s:RenderStats(a:days)
    return
  endif

  botright new
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nowrap nonumber norelativenumber signcolumn=no foldcolumn=0
  setlocal cursorline
  silent file [Onesimus\ Stats]
  let b:onesimus_stats_buffer = 1
  nnoremap <silent><buffer> q :close<CR>
  nnoremap <silent><buffer> r :call <SID>RenderStats(b:onesimus_stats_days)<CR>
  nnoremap <silent><buffer> 7 :call <SID>RenderStats(7)<CR>
  nnoremap <silent><buffer> 3 :call <SID>RenderStats(30)<CR>
  nnoremap <silent><buffer> 9 :call <SID>RenderStats(90)<CR>
  call s:RenderStats(a:days)

  syntax clear
  syntax match OnesimusStatsTitle /^ONESIMUS.*$/
  syntax match OnesimusStatsSection /^  [A-Z][A-Z ,]*$/
  syntax match OnesimusStatsBar /[█░#.]\{4,}/
  syntax match OnesimusStatsMuted /^  Local session.*$/
  syntax match OnesimusStatsMuted /^  Data:.*$/
  highlight default link OnesimusStatsTitle Title
  highlight default link OnesimusStatsSection Statement
  highlight default link OnesimusStatsBar Identifier
  highlight default link OnesimusStatsMuted Comment
endfunction

function! s:StatsDays(value) abort
  let l:days = empty(a:value) ? 30 : str2nr(a:value)
  return index([7, 30, 90], l:days) >= 0 ? l:days : 30
endfunction

function! s:CompleteStats(arglead, cmdline, cursorpos) abort
  return filter(['7', '30', '90'], 'v:val =~# "^".a:arglead')
endfunction

function! s:ResetStats(bang) abort
  if a:bang !=# '!'
    echohl WarningMsg
    echomsg 'Use :OnesimusStatsReset! to delete local usage journals.'
    echohl None
    return
  endif

  " Never recursively delete the configurable root.  In particular, a typo
  " such as g:onesimus_usage_state_dir = '~' must not turn a dashboard reset
  " into deletion of unrelated data.  Follow only real YYYY-MM directories
  " (not symlinks), and remove only journal filenames Onesimus owns.
  for l:month in globpath(s:StateRoot(), '????-??', 0, 1)
    if getftype(l:month) !=# 'dir'
          \ || fnamemodify(l:month, ':t') !~# '^\d\{4}-\d\{2}$'
      continue
    endif
    for l:file in globpath(l:month, '*.json*', 0, 1)
      let l:name = fnamemodify(l:file, ':t')
      if getftype(l:file) ==# 'file'
            \ && l:name =~# '^\d\{8}-\d\{6}-\d\+\.json\%(.tmp\)\?$'
        silent! call delete(l:file)
      endif
    endfor
    silent! call delete(l:month, 'd')
  endfor
  let g:onesimus_usage_runtime = s:NewRuntime()
  let s:runtime = g:onesimus_usage_runtime
  " Do not recreate an empty journal at VimLeavePre.  The next observation or
  " explicit action will make this fresh runtime dirty again.
  let s:runtime.dirty = 0
  echomsg 'Onesimus local usage journals cleared.'
endfunction

function! s:DisableStats() abort
  let g:onesimus_usage_enabled = 0
  echomsg 'Onesimus local usage journal disabled for this Vim process.'
endfunction

command! -nargs=? -complete=customlist,<SID>CompleteStats OnesimusStats
      \ call <SID>OpenStats(<SID>StatsDays(<q-args>))
command! -nargs=? -complete=customlist,<SID>CompleteStats OnesimusUsage
      \ call <SID>OpenStats(<SID>StatsDays(<q-args>))
command! -bang OnesimusStatsReset call <SID>ResetStats('<bang>')
command! OnesimusStatsPath echomsg <SID>StateRoot()
command! OnesimusStatsDisable call <SID>DisableStats()

augroup onesimus_usage
  autocmd!
  autocmd FileType * call OnesimusObserveFiletype(&l:filetype)
  autocmd ColorScheme * call OnesimusTrackOnce('theme.'.expand('<amatch>'))
  autocmd VimLeavePre * call OnesimusUsageFlush()
augroup END

call s:OfferSessionFeatures()
if !empty(&filetype)
  call OnesimusObserveFiletype(&filetype)
endif
if exists('g:colors_name')
  call OnesimusTrackOnce('theme.'.g:colors_name)
endif
if exists('*OnesimusJiebaReady') && OnesimusJiebaReady()
  call OnesimusTrackOnce('writing.cjk')
endif
