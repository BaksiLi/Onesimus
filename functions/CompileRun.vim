" CompileRun.vim - one-key, asynchronous compilation and execution
" Author: BaksiLi
" Version: 0.2.0

let g:compilerun_term = get(g:, 'compilerun_term', -1)
let g:asyncrun_open = get(g:, 'asyncrun_open', 8)
let g:asyncrun_bell = get(g:, 'asyncrun_bell', 1)
let g:compilerun_timer = get(g:, 'compilerun_timer', 1)

let s:supported_filetypes = [
      \ 'c', 'cpp', 'dot', 'go', 'haskell', 'html', 'java', 'markdown',
      \ 'python', 'ruby', 'rust', 'sh', 'tex', 'typescript', 'vim',
      \ ]

function! s:Error(message) abort
  echohl ErrorMsg
  echomsg 'Onesimus: '.a:message
  echohl None
  return 0
endfunction

function! s:Platform() abort
  if exists('g:asc_uname')
    return g:asc_uname
  endif
  if has('win32') || has('win64')
    return 'windows'
  endif
  return has('macunix') ? 'darwin' : 'posix'
endfunction

function! s:FirstExecutable(candidates) abort
  for l:candidate in a:candidates
    if executable(l:candidate)
      return l:candidate
    endif
  endfor
  return ''
endfunction

function! s:OpenPlan(path) abort
  let l:platform = s:Platform()
  if l:platform ==# 'darwin'
    return {'command': 'open '.shellescape(a:path), 'requires': ['open']}
  elseif l:platform ==# 'windows'
    " start is a cmd.exe built-in; the empty title keeps a quoted path from
    " being mistaken for the window title.
    return {'command': 'cmd /c start "" '.shellescape(a:path), 'requires': []}
  elseif l:platform ==# 'cygwin'
    return {'command': 'cygstart '.shellescape(a:path), 'requires': ['cygstart']}
  endif
  return {'command': 'xdg-open '.shellescape(a:path), 'requires': ['xdg-open']}
endfunction

function! s:OutputPath(source) abort
  let l:output = fnamemodify(a:source, ':r')
  return s:Platform() ==# 'windows' ? l:output.'.exe' : l:output
endfunction

function! s:Timed(command) abort
  if !g:compilerun_timer || s:Platform() ==# 'windows'
    return a:command
  endif
  " A nested shell makes `time` cover the complete compile-and-run chain,
  " while shellescape() preserves the already quoted paths as one argument.
  return 'time sh -c '.shellescape(a:command)
endfunction

function! s:Plan(filetype, source) abort
  let l:directory = fnamemodify(a:source, ':h')
  let l:options = {'cwd': l:directory}
  let l:path = shellescape(a:source)

  if a:filetype ==# 'sh'
    return {'command': 'bash '.l:path, 'options': extend(l:options, {'raw': 1}),
          \ 'requires': ['bash'], 'timed': 1}
  elseif a:filetype ==# 'python'
    let l:python = s:FirstExecutable(['python3', 'python'])
    return {'command': (empty(l:python) ? 'python3' : l:python).' '.l:path,
          \ 'options': extend(l:options, {'raw': 1}),
          \ 'requires': [empty(l:python) ? 'python3' : l:python], 'timed': 1}
  elseif a:filetype ==# 'ruby'
    return {'command': 'ruby '.l:path, 'options': extend(l:options, {'raw': 1}),
          \ 'requires': ['ruby'], 'timed': 1}
  elseif a:filetype ==# 'html'
    let l:open = s:OpenPlan(a:source)
    return {'command': l:open.command, 'options': l:options,
          \ 'requires': l:open.requires, 'timed': 0}
  elseif a:filetype ==# 'haskell'
    return {'command': 'ghc '.l:path, 'options': l:options,
          \ 'requires': ['ghc'], 'timed': 1}
  elseif a:filetype ==# 'go'
    return {'command': 'go run '.l:path, 'options': extend(l:options, {'raw': 1}),
          \ 'requires': ['go'], 'timed': 1}
  elseif a:filetype ==# 'dot'
    let l:image = fnamemodify(a:source, ':r').'.png'
    let l:open = s:OpenPlan(l:image)
    return {
          \ 'command': 'dot -Tpng '.l:path.' -o '.shellescape(l:image)
          \   .' && '.l:open.command,
          \ 'options': l:options,
          \ 'requires': ['dot'] + l:open.requires,
          \ 'timed': 1,
          \ }
  elseif a:filetype ==# 'c' || a:filetype ==# 'cpp'
    let l:compiler = a:filetype ==# 'c' ? 'gcc' : 'g++'
    let l:output = s:OutputPath(a:source)
    return {
          \ 'command': l:compiler.' -Wall -O2 '.l:path.' -o '.shellescape(l:output)
          \   .' && '.shellescape(l:output),
          \ 'options': l:options,
          \ 'requires': [l:compiler],
          \ 'timed': 1,
          \ }
  elseif a:filetype ==# 'java'
    let l:class = fnamemodify(a:source, ':t:r')
    return {
          \ 'command': 'javac '.l:path.' && java -cp '.shellescape(l:directory)
          \   .' '.shellescape(l:class),
          \ 'options': l:options,
          \ 'requires': ['javac', 'java'],
          \ 'timed': 1,
          \ }
  elseif a:filetype ==# 'rust'
    let l:output = s:OutputPath(a:source)
    return {
          \ 'command': 'rustc '.l:path.' -o '.shellescape(l:output)
          \   .' && '.shellescape(l:output),
          \ 'options': l:options,
          \ 'requires': ['rustc'],
          \ 'timed': 1,
          \ }
  elseif a:filetype ==# 'typescript'
    let l:javascript = fnamemodify(a:source, ':r').'.js'
    return {
          \ 'command': 'tsc '.l:path.' && node '.shellescape(l:javascript),
          \ 'options': l:options,
          \ 'requires': ['tsc', 'node'],
          \ 'timed': 1,
          \ }
  endif
  return {}
endfunction

function! s:Dispatch(options, command) abort
  if exists('g:onesimus_compilerun_runner')
    return call(g:onesimus_compilerun_runner, ['', a:options, a:command])
  endif
  if !exists('*asyncrun#run')
    return s:Error('AsyncRun is unavailable; run :PlugInstall asyncrun.vim.')
  endif
  return asyncrun#run('', a:options, a:command)
endfunction

function! s:CompileRun() abort
  let l:filetype = tolower(&l:filetype)
  if index(s:supported_filetypes, l:filetype) < 0
    return s:Error('cannot run filetype '.(empty(l:filetype) ? '(none)' : l:filetype).'.')
  endif

  if empty(bufname('%'))
    return s:Error('save this buffer before running it.')
  endif
  let l:source = expand('%:p')

  try
    update
  catch
    return s:Error('could not save '.fnamemodify(l:source, ':t').': '.v:exception)
  endtry

  if exists('*OnesimusTrack')
    call OnesimusTrack('code.run')
  endif

  if l:filetype ==# 'markdown'
    if exists(':MarkdownPreview') == 2
      MarkdownPreview
      echomsg 'Markdown preview toggled.'
      return 1
    endif
    return s:Error('Markdown preview is unavailable; run :PlugInstall markdown-preview.nvim.')
  elseif l:filetype ==# 'tex'
    if exists(':VimtexCompile') == 2
      VimtexCompile
      return 1
    endif
    return s:Error('VimTeX is unavailable; run :PlugInstall vimtex.')
  elseif l:filetype ==# 'vim'
    execute 'source '.fnameescape(l:source)
    return 1
  endif

  let l:plan = s:Plan(l:filetype, l:source)
  for l:program in l:plan.requires
    if !executable(l:program)
      return s:Error(l:program.' is required to run this file.')
    endif
  endfor

  let l:command = l:plan.timed ? s:Timed(l:plan.command) : l:plan.command
  try
    call s:Dispatch(l:plan.options, l:command)
  catch
    return s:Error('could not start the task: '.v:exception)
  endtry
  return 1
endfunction

command! -bang -nargs=0 CompileRun call <SID>CompileRun()

" Add range support for asyncrun.
command! -bang -range=% -nargs=* AsyncRunRange call asyncrun#run('<bang>', {}, <q-args>)
