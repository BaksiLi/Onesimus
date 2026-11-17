" One Vim owns one browser reader. The host keeps save/build policy.

let s:browser = get(s:, 'browser', {})
let s:command = ['python3', fnamemodify(resolve(expand('<sfile>:p')), ':h:h:h').'/bin/webpreview']

function! webpreview#tex#current(...) abort
  if &l:filetype !=# 'tex'
    call webpreview#notify('TEX PREVIEW', ['Open a TeX source to preview it.'], 1)
    return 0
  endif
  let l:state = get(b:, 'vimtex', {})
  let l:main = get(l:state, 'tex', expand('%:p'))
  let l:root = get(l:state, 'root', fnamemodify(l:main, ':h'))
  let l:compiler = get(l:state, 'compiler', {})
  let l:pdf = has_key(l:compiler, 'get_file') ? l:compiler.get_file('pdf') : fnamemodify(l:main, ':r').'.pdf'
  let l:files = has_key(l:state, 'get_sources') ? l:state.get_sources() : [l:main]
  let l:fls = has_key(l:compiler, 'get_file') ? l:compiler.get_file('fls') : fnamemodify(l:pdf, ':r').'.fls'
  if filereadable(l:fls)
    for l:line in readfile(l:fls)
      if l:line =~# '^INPUT ' | call add(l:files, strpart(l:line, 6)) | endif
    endfor
  endif
  let l:inputs = [l:main]
  let l:root = fnamemodify(resolve(l:root), ':p')
  for l:file in l:files
    let l:path = l:file =~# '^\%(/\|\a:[/\\]\)' ? l:file : l:root.'/'.l:file
    let l:path = resolve(fnamemodify(l:path, ':p'))
    if stridx(l:path, l:root) == 0 && filereadable(l:path) && l:path !=# l:pdf
          \ && l:path =~# '\.\%(tex\|ltx\|bib\|sty\|cls\|bst\|png\|jpe\?g\|pdf\|eps\)$'
      call add(l:inputs, l:path)
    endif
  endfor
  let l:diff = {'event': 'diff', 'files': uniq(sort(l:inputs)),
        \ 'engine': has_key(l:compiler, 'get_engine') ? l:compiler.get_engine() : '-pdf'}
  if a:0
    let l:diff.base = filereadable(expand(a:1)) ? fnamemodify(expand(a:1), ':p') : a:1
  endif
  return webpreview#tex#open(l:pdf, l:main, {'reuse': 1, 'diff': l:diff})
endfunction

function! s:BrowserReady(reader, channel, line) abort
  if a:reader isnot s:browser | return | endif
  let l:event = json_decode(a:line)
  if l:event.event ==# 'ready'
    let a:reader.url = l:event.url
    call s:ShowBrowser(a:reader)
    call webpreview#show(a:reader.url)
    for l:key in ['diff', 'forward']
      if has_key(a:reader, l:key)
        call ch_sendraw(a:channel, json_encode(remove(a:reader, l:key))."\n")
      endif
    endfor
  elseif l:event.event ==# 'source'
    let a:reader.pending_source = l:event
    call s:ResumeSource()
  elseif l:event.event ==# 'open'
    call s:ShowBrowser(a:reader)
    call webpreview#show(a:reader.url)
  elseif l:event.event ==# 'error'
    call webpreview#notify('PDF POSITION', [l:event.message], 1)
  endif
endfunction

function! s:ShowBrowser(reader) abort
  let l:host = get(g:, 'webpreview_host', '127.0.0.1')
  let l:url = substitute(a:reader.url, '127\.0\.0\.1', l:host, '')
  let l:lines = [
        \ l:url,
        \ fnamemodify(a:reader.pdf, ':~:.'),
        \ 'Locate in source: tap a point, or select text to enter Vim Visual.',
        \ 'Built PDF; unsaved edits are absent.',
        \ 'Zellij detach keeps this link; quitting Vim ends it.',
        \ ]
  if l:host ==# '127.0.0.1' && webpreview#headless()
    call add(l:lines, 'Forward this loopback port, or configure your private relay hostname locally.')
  endif
  call webpreview#notify('PDF BROWSER', l:lines, 0)
endfunction

function! s:BrowserError(reader, channel, line) abort
  if a:reader isnot s:browser | return | endif
  " stderr is a diagnostic stream, not one notification per traceback line.
  echomsg 'PDF reader: '.a:line
endfunction

function! s:BrowserExited(reader, job, status) abort
  if a:reader is s:browser && has_key(a:reader, 'next')
    call webpreview#tex#open(a:reader.next.pdf,
          \ a:reader.next.main, a:reader.next.options)
    return
  endif
  if a:reader is s:browser
    let s:browser = {}
    if a:status != 0
      call webpreview#notify('PDF READER STOPPED', [
            \ 'Reader exited with status '.a:status.'. Details: :messages',
            \ 'Use :WebPreview to start it again.'], 1)
    endif
  endif
endfunction

function! webpreview#tex#open(pdf, main, ...) abort
  let l:options = get(a:000, 0, {})
  let l:running = has_key(s:browser, 'job') && job_status(s:browser.job) ==# 'run'
  if l:running && !has_key(s:browser, 'next')
        \ && s:browser.pdf ==# a:pdf && s:browser.main ==# a:main
    for l:key in ['diff', 'forward']
      if has_key(l:options, l:key)
        if has_key(s:browser, 'url')
          call ch_sendraw(job_getchannel(s:browser.job),
                \ json_encode(l:options[l:key])."\n")
        else
          let s:browser[l:key] = l:options[l:key]
        endif
      endif
    endfor
    if get(l:options, 'show', 1) && has_key(s:browser, 'url')
      if get(l:options, 'reuse', 0)
        call ch_sendraw(job_getchannel(s:browser.job), json_encode({'event': 'open'})."\n")
      else
        call s:ShowBrowser(s:browser)
        call webpreview#show(s:browser.url)
      endif
    endif
    return 1
  endif
  if !filereadable(a:pdf)
    call webpreview#notify('PDF NOT BUILT YET', ['Build the paper first: '.a:pdf], 1)
    return 0
  endif
  if l:running
    let s:browser.next = {'pdf': a:pdf, 'main': a:main, 'options': l:options}
    call job_stop(s:browser.job)
    return 1
  endif
  let l:command = copy(get(g:, 'webpreview_tex_command', s:command))
  if !executable(l:command[0])
    call webpreview#notify('PDF BROWSER UNAVAILABLE', ['Executable not found: '.l:command[0]], 1)
    return 0
  endif
  let s:browser = {'pdf': a:pdf, 'main': a:main}
  for l:key in ['diff', 'forward']
    if has_key(l:options, l:key)
      let s:browser[l:key] = l:options[l:key]
    endif
  endfor
  let l:command += [
        \ '--pdf', a:pdf, '--editor', a:main, '--serve',
        \ '--url-host', get(g:, 'webpreview_host', '127.0.0.1'),
        \ '--port', string(get(g:, 'webpreview_tex_port', 0))]
  let s:browser.job = job_start(l:command, {
        \ 'in_io': 'pipe',
        \ 'out_cb': function('s:BrowserReady', [s:browser]),
        \ 'err_cb': function('s:BrowserError', [s:browser]),
        \ 'exit_cb': function('s:BrowserExited', [s:browser]),
        \ })
  return job_status(s:browser.job) !=# 'fail'
endfunction

" Following never starts or retargets a reader: it moves the one already open for this PDF.
function! webpreview#tex#follow(pdf, main, position) abort
  if !has_key(s:browser, 'job') || job_status(s:browser.job) !=# 'run'
        \ || has_key(s:browser, 'next') || !has_key(s:browser, 'url')
        \ || s:browser.pdf !=# a:pdf || s:browser.main !=# a:main
    return 0
  endif
  call ch_sendraw(job_getchannel(s:browser.job),
        \ json_encode(extend(copy(a:position), {'follow': v:true}))."\n")
  return 1
endfunction

function! webpreview#tex#stop() abort
  let l:reader = s:browser
  let s:browser = {}
  if has_key(l:reader, 'job') | call job_stop(l:reader.job) | endif
endfunction

function! s:ResumeSource() abort
  if mode(1) !~# '^n' || !has_key(s:browser, 'pending_source') | return | endif
  call webpreview#locate(remove(s:browser, 'pending_source'))
endfunction


augroup webpreview_tex
  autocmd!
  autocmd SafeState * call <SID>ResumeSource()
  autocmd VimLeavePre * call webpreview#tex#stop()
augroup END
