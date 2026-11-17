" Renderers own their sessions and document semantics; this is the Vim interface.
function! webpreview#setup() abort
  let g:cogitatum_preview_host = get(g:, 'cogitatum_preview_host',
        \ get(g:, 'webpreview_host', '127.0.0.1'))
  let g:cogitatum_preview_browserfunc = get(g:, 'cogitatum_preview_browserfunc', 'webpreview#show')
  let g:cogitatum_preview_selectfunc = get(g:, 'cogitatum_preview_selectfunc', 'webpreview#select')
endfunction

function! webpreview#headless() abort
  if !empty($SSH_CONNECTION) || !empty($SSH_TTY) || !empty($MOSH_CONNECTION)
    return 1
  endif
  return !(has('macunix') || has('win32') || has('win64')
        \ || has('gui_running') || !empty($DISPLAY) || !empty($WAYLAND_DISPLAY))
endfunction

function! webpreview#external(target) abort
  let l:opener = has('macunix') ? ['open']
        \ : (has('win32') || has('win64') ? ['cmd', '/c', 'start', '']
        \ : ['xdg-open'])
  return job_status(job_start(l:opener + [a:target], {'stoponexit': ''})) !=# 'fail'
endfunction

function! webpreview#browser(url) abort
  if webpreview#headless() | return 0 | endif
  let l:browser = get(g:, 'webpreview_browser', '')
  if empty(l:browser) | return webpreview#external(a:url) | endif
  let l:opener = has('macunix') ? ['open', '-a', l:browser] : [l:browser]
  return job_status(job_start(l:opener + [a:url], {'stoponexit': ''})) !=# 'fail'
endfunction

function! webpreview#url(url) abort
  return substitute(a:url, '://\zs\%(localhost\|127\.0\.0\.1\)',
        \ get(g:, 'webpreview_host', '127.0.0.1'), '')
endfunction

function! webpreview#show(url) abort
  return call(get(g:, 'webpreview_browserfunc', 'webpreview#browser'), [webpreview#url(a:url)])
endfunction

function! webpreview#notify(title, lines, error) abort
  if has_key(g:, 'webpreview_notify')
    return call(g:webpreview_notify, [a:title, a:lines, a:error])
  endif
  if a:error | echohl ErrorMsg | endif
  echomsg a:title.': '.join(a:lines, "\n")
  echohl None
endfunction

function! s:Command(command, label) abort
  if exists(':'.a:command) != 2
    call webpreview#notify('PREVIEW UNAVAILABLE', ['Install '.a:label.' to preview this document.'], 1)
    return 0
  endif
  execute a:command
  return 1
endfunction

function! webpreview#open() abort
  if &l:buftype !=# '' | return 0 | endif
  let l:handler = get(get(g:, 'webpreview_open', {}), &l:filetype, '')
  if !empty(l:handler) | return call(l:handler, []) | endif
  if &l:filetype ==# 'tex'
    return webpreview#tex#current()
  elseif &l:filetype ==# 'cogitatum'
    return webpreview#inquiry()
  elseif &l:filetype ==# 'markdown'
    return webpreview#markdown#open()
  endif
  call webpreview#notify('PREVIEW UNAVAILABLE', ['No preview provider for '.&l:filetype.'.'], 1)
  return 0
endfunction

function! webpreview#inquiry() abort
  return s:Command('CogPreview', 'vim-cogitatum')
endfunction

function! webpreview#stop() abort
  if &l:filetype ==# 'tex'
    call webpreview#tex#stop()
  else
    if &l:filetype ==# 'markdown'
      call webpreview#markdown#stop()
    endif
    if exists(':CogPreviewStop') == 2
      CogPreviewStop
    endif
  endif
endfunction

" Select only a unique literal match in the located paragraph. Rendered TeX
" may differ from source; a point is more useful than an invented range.
function! webpreview#locate(position) abort
  let l:file = a:position.file
  if !filereadable(l:file) && bufnr(l:file) < 0
    call webpreview#notify('SOURCE UNAVAILABLE', [l:file], 1)
    return 0
  endif
  let l:buffer = bufnr(l:file)
  let l:windows = win_findbuf(l:buffer)
  if !empty(l:windows)
    call win_gotoid(l:windows[0])
  elseif l:buffer >= 0
    execute 'hide buffer '.l:buffer
  else
    execute 'hide edit '.fnameescape(l:file)
  endif
  normal! m'
  call cursor(a:position.line, a:position.column)
  normal! zvzz
  if get(a:position, 'approximate', 0)
    call webpreview#notify('NEARBY SOURCE', [
          \ 'This comparison passage was removed or has no exact source match.',
          \ 'Located the nearest surviving manuscript line.'], 0)
    return 1
  endif
  if has_key(a:position, 'text')
    if webpreview#select(a:position.text, a:position.line,
          \ get(a:position, 'end_line', a:position.line))
      return 1
    endif
    call webpreview#notify('SOURCE LOCATED', [
          \ 'Selected preview text has no unique literal match in this source paragraph.',
          \ 'Located the built passage; TeX markup or draft edits may differ.'], 0)
    return 1
  endif
  if &l:modified
    call webpreview#notify('LOCATED IN DRAFT', [
          \ 'Unsaved edits are preserved. Positions refer to the previewed revision.',
          \ ], 0)
  endif
  return 1
endfunction

function! webpreview#select(text, line, ...) abort
  let l:first = min([a:line, get(a:000, 0, a:line)])
  let l:last = max([a:line, get(a:000, 0, a:line)])
  let l:first = max([1, min([line('$'), l:first])])
  let l:last = max([1, min([line('$'), l:last])])
  while l:first > 1 && getline(l:first - 1) !~# '^\s*$'
    let l:first -= 1
  endwhile
  while l:last < line('$') && getline(l:last + 1) !~# '^\s*$'
    let l:last += 1
  endwhile
  let l:words = split(a:text)
  if empty(l:words) | return 0 | endif
  let l:pattern = '\C\V'.join(map(l:words, 'escape(v:val, "\\")'), '\_s\+')
  let l:source = join(getline(l:first, l:last), "\n")
  let l:match = matchstrpos(l:source, l:pattern)
  if l:match[1] < 0 || match(l:source, l:pattern, l:match[1] + 1) >= 0
    return 0
  endif
  let l:start = s:TextPosition(l:source, l:match[1], l:first)
  let l:end_offset = l:match[2]
  if &selection !=# 'exclusive'
    let l:end_offset -= strlen(matchstr(l:match[0], '.$'))
  endif
  let l:end = s:TextPosition(l:source, l:end_offset, l:first)
  call cursor(l:start)
  normal! zv
  normal! v
  call cursor(l:end)
  normal! zv
  return 1
endfunction

function! s:TextPosition(text, offset, first) abort
  let l:before = strpart(a:text, 0, a:offset)
  return [a:first + count(l:before, "\n"), a:offset - strridx(l:before, "\n")]
endfunction

