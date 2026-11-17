" The Onesimus command surface.  `:One` opens the action guide and
" `:One {verb} [argument]` runs an action.  This file owns the verb names,
" their keys and their labels; each module registers its implementations with
" one#define(), so one verb can mean "build" in TeX, Markdown and Python alike.

let s:impl = get(s:, 'impl', {})
let s:arguments = get(s:, 'arguments', {})

" Current-file actions under \\.  A letter means the same action in every
" filetype; a buffer without that action hides the row instead of lending the
" letter to something else.
let s:file_menu = [
      \ ['b', 'build', 'Build & show  (F5)'],
      \ ['v', 'view', 'Show cursor in preview'],
      \ ['s', 'save', 'Save safely'],
      \ ['e', 'errors', 'Problems'],
      \ ['t', 'outline', 'Outline  (F2)'],
      \ ['f', 'format', 'Format  (F6)'],
      \ ['d', 'diff', 'Show changes'],
      \ ['w', 'words', 'Word count'],
      \ ['z', 'focus', 'Focus mode'],
      \ ['m', 'math', 'Rendered formulas'],
      \ ['p', 'spell', 'Spelling marks'],
      \ ['l', 'sentences', 'One sentence per line'],
      \ ['r', 'read', 'Terminal Reading'],
      \ ['c', 'map', 'Terminal Map'],
      \ ['i', 'inquiry', 'Preview inquiry fences'],
      \ ['n', 'rename', 'Rename symbol'],
      \ ['a', 'action', 'Code action'],
      \ ['h', 'health', 'Tool status'],
      \ ['?', 'help', 'Help for this file'],
      \ ]

" Shown instead of the file menu while the buffer and its file disagree.
let s:conflict_menu = [
      \ ['d', 'compare', 'Compare buffer with disk'],
      \ ['u', 'revert', 'Use disk version  [discard buffer]'],
      \ ['x', 'overwrite', 'Save reviewed buffer over disk'],
      \ ['?', 'help', 'Conflict & collaboration help'],
      \ ]

" Global groups under \.  Each row is [key, Ex command, label].
let s:global_menu = [
      \ ['f', 'Find', [
      \   ['f', 'One find files', 'Files'],
      \   ['g', 'One find git_files', 'Git files'],
      \   ['b', 'One find buffers', 'Buffers'],
      \   ['w', 'One find grep', 'Search project'],
      \   ['h', 'One find history', 'Recent files'],
      \   ['t', 'One find tags', 'Buffer tags'],
      \   ['T', 'One find proj_tags', 'Project tags'],
      \   ['m', 'One find marks', 'Marks'],
      \   ['c', 'One find command_history', 'Command history']]],
      \ ['g', 'Git', [
      \   ['s', 'Git', 'Status'],
      \   ['d', 'Gdiffsplit', 'Diff'],
      \   ['b', 'Git blame', 'Blame'],
      \   ['l', 'Git log', 'Log']]],
      \ ['t', 'Toggle', [
      \   ['r', 'One numbers', 'Relative numbers'],
      \   ['i', 'One indent', 'Indent guides'],
      \   ['p', 'One parens', 'Parenthesis colours'],
      \   ['b', 'One background', 'Light / dark'],
      \   ['d', 'One redraw', 'Redraw screen  (Ctrl-L)']]],
      \ ['o', 'Onesimus', [
      \   ['h', 'One home', 'Home'],
      \   ['c', 'One config', 'Edit config'],
      \   ['r', 'One reload', 'Reload config'],
      \   ['u', 'One update', 'Update Onesimus'],
      \   ['p', 'One snapshot', 'Snapshot plugins'],
      \   ['s', 'One usage', 'Local usage']]],
      \ ]

let s:function_keys = {'<F2>': 'outline', '<F3>': 'tree', '<F4>': 'repl',
      \ '<F5>': 'build', '<F6>': 'format'}

" Register {Run} for {verb} in buffers of {kinds}: a filetype, 'writing' for
" any prose buffer, or '*' for anywhere; a list registers several at once.
" {Run} is a Funcref, called with the argument when one was typed, or an Ex
" command, which receives the argument as text.  An optional {When} Funcref
" hides the verb while it returns false.
function! one#define(verb, kinds, Run, ...) abort
  let l:entry = {'run': a:Run}
  if a:0
    let l:entry.when = a:1
  endif
  let l:impl = get(s:impl, a:verb, {})
  for l:kind in type(a:kinds) == v:t_list ? a:kinds : [a:kinds]
    let l:impl[l:kind] = l:entry
  endfor
  let s:impl[a:verb] = l:impl
endfunction

" Completions for a verb's argument: a list, or a getcompletion() type.
function! one#arguments(verb, values) abort
  let s:arguments[a:verb] = a:values
endfunction

" :One help is contextual; \? always opens the distribution manual.
function! one#help() abort
  call OnesimusTrack('meta.help')
  execute 'helptags '.fnameescape($VIMRCDIR.'/doc')
  help onesimus
endfunction

function! s:Handler(verb) abort
  let l:impl = get(s:impl, a:verb, {})
  let l:writing = exists('*OnesimusIsWritingBuffer')
        \ && OnesimusIsWritingBuffer(bufnr('%'))
  for l:kind in [&l:filetype, l:writing ? 'writing' : '', '*']
    let l:entry = get(l:impl, l:kind, {})
    if !empty(l:entry) && (!has_key(l:entry, 'when') || l:entry.when())
      return l:entry
    endif
  endfor
  return {}
endfunction

function! one#available(verb) abort
  return !empty(s:Handler(a:verb))
endfunction

function! one#run(args) abort
  let l:verb = matchstr(a:args, '^\S\+')
  if empty(l:verb)
    return OnesimusGuide()
  endif
  let l:argument = trim(a:args[len(l:verb):])
  let l:entry = s:Handler(l:verb)
  if empty(l:entry)
    echohl WarningMsg
    echomsg has_key(s:impl, l:verb)
          \ ? ':One '.l:verb.' is not available in this buffer.'
          \ : 'Unknown action :One '.l:verb.'  (Tab lists actions)'
    echohl None
    return
  endif
  if type(l:entry.run) == v:t_func
    return call(l:entry.run, empty(l:argument) ? [] : [l:argument])
  endif
  execute l:entry.run.(empty(l:argument) ? '' : ' '.l:argument)
endfunction

function! one#complete(lead, line, position) abort
  let l:typed = substitute(strpart(a:line, 0, a:position), '^\s*\S\+\s*', '', '')
  let l:words = split(l:typed, '\s\+', 1)
  if len(l:words) <= 1
    return sort(filter(keys(s:impl),
          \ {_, verb -> stridx(verb, a:lead) == 0 && one#available(verb)}))
  endif
  let l:values = get(s:arguments, l:words[0], [])
  if type(l:values) == v:t_string
    return getcompletion(a:lead, l:values)
  endif
  return filter(copy(l:values), {_, value -> stridx(value, a:lead) == 0})
endfunction

" Menu rows [key, Ex command, label] for the current buffer.
function! one#file_menu() abort
  let l:conflict = exists('*OnesimusHasExternalConflict')
        \ && OnesimusHasExternalConflict()
  " A deleted file leaves nothing to compare or revert to; x recreates it.
  let l:deleted = l:conflict && !filereadable(expand('%:p'))
  let l:rows = []
  for [l:key, l:verb, l:label] in l:conflict ? s:conflict_menu : s:file_menu
    if l:deleted && index(['compare', 'revert'], l:verb) >= 0
      continue
    endif
    if one#available(l:verb)
      call add(l:rows, [l:key, 'One '.l:verb,
            \ l:deleted && l:verb ==# 'overwrite'
            \ ? 'Recreate deleted file from buffer' : l:label])
    endif
  endfor
  return l:rows
endfunction

" \\{key}: the same letter follows the menu the buffer shows right now.
function! one#key(key) abort
  for [l:key, l:command, l:label] in one#file_menu()
    if l:key ==# a:key
      execute l:command
      return
    endif
  endfor
  echohl WarningMsg
  echomsg '\\'.a:key.' is not available in this buffer.  (\\ shows what is)'
  echohl None
endfunction

function! one#global_menu() abort
  return deepcopy(s:global_menu)
endfunction

" The guide, \\ and the function keys all come from the tables above, so a key
" shown in the guide is also a real mapping that runs at once when typed
" without a pause.
function! one#map() abort
  " \ waits 'timeoutlen' for a second key.  A pause shows the menu, so the
  " guide doubles as the reminder for every chord it lists.
  nnoremap <silent> <Leader> :<C-U>One<CR>
  nnoremap <silent> <Leader><Leader> :<C-U>call OnesimusGuide('context')<CR>
  nnoremap <silent> <Leader>? :<C-U>call one#help()<CR>
  for [l:group, l:title, l:rows] in s:global_menu
    for [l:key, l:command, l:label] in l:rows
      execute 'nnoremap <silent> <Leader>'.l:group.l:key.' :<C-U>'.l:command.'<CR>'
    endfor
  endfor
  let l:keys = {}
  for [l:key, l:verb, l:label] in s:file_menu + s:conflict_menu
    let l:keys[l:key] = 1
  endfor
  for l:key in keys(l:keys)
    execute 'nnoremap <silent> <Leader><Leader>'.l:key
          \ .' :<C-U>call one#key('.string(l:key).')<CR>'
  endfor
  for [l:key, l:verb] in items(s:function_keys)
    execute 'nnoremap <silent> '.l:key.' :<C-U>One '.l:verb.'<CR>'
  endfor
endfunction
