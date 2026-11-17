" One live Markdown document in a Vim-owned session, including unsaved text.
let s:preview = get(s:, 'preview', {})
let s:command = ['python3', fnamemodify(resolve(expand('<sfile>:p')), ':h:h:h').'/bin/webpreview']

function! s:Show(url) abort
  let l:url = webpreview#url(a:url)
  call webpreview#notify('MARKDOWN PREVIEW', [l:url,
        \ 'Live draft, including unsaved edits. Save separately.',
        \ 'The preview belongs to this Vim session.'], 0)
  call webpreview#show(l:url)
endfunction

function! s:Send(message) abort
  call ch_sendraw(job_getchannel(s:preview.job), json_encode(a:message)."\n")
endfunction

function! s:Source(...) abort
  let l:buffer = s:preview.buffer
  call s:Send({'event': 'source', 'file': fnamemodify(bufname(l:buffer), ':p'),
        \ 'text': join(getbufline(l:buffer, 1, '$'), "\n")})
endfunction

function! s:Cursor() abort
  call s:Send({'event': 'cursor', 'line': line('.'), 'column': col('.')})
endfunction

function! s:Schedule() abort
  call timer_stop(get(s:preview, 'timer', -1))
  let s:preview.timer = timer_start(120, function('s:Source'))
endfunction

function! s:Resume() abort
  if mode(1) !~# '^n' || !has_key(s:preview, 'pending') | return | endif
  let l:position = remove(s:preview, 'pending')
  if webpreview#locate(l:position) && get(l:position, 'event', '') ==# 'file'
    call webpreview#open()
  endif
endfunction

function! s:Output(preview, channel, line) abort
  if a:preview isnot s:preview | return | endif
  let l:event = json_decode(a:line)
  if l:event.event ==# 'ready'
    let s:preview.url = l:event.url
    call s:Source()
    call s:Cursor()
    call s:Show(s:preview.url)
  elseif l:event.event ==# 'open'
    call s:Show(s:preview.url)
  elseif index(['source', 'file'], l:event.event) >= 0
    let s:preview.pending = extend(l:event, {'line': get(l:event, 'line', 1), 'column': 1})
    call s:Resume()
  elseif l:event.event ==# 'error'
    call webpreview#notify('MARKDOWN PREVIEW', [l:event.message], 1)
  endif
endfunction

function! s:Error(preview, channel, line) abort
  if a:preview is s:preview | echomsg 'Markdown reader: '.a:line | endif
endfunction

function! s:Exited(preview, job, status) abort
  if a:preview isnot s:preview | return | endif
  call webpreview#markdown#stop()
  if a:status
    call webpreview#notify('MARKDOWN READER STOPPED', ['Details: :messages. Reopen with :WebPreview.'], 1)
  endif
endfunction

function! webpreview#markdown#open() abort
  if empty(bufname(''))
    call webpreview#notify('NAME THIS DRAFT', ['Use :file draft.md; preview does not save it.'], 1)
    return 0
  endif
  let l:running = has_key(s:preview, 'job') && job_status(s:preview.job) ==# 'run'
  if !l:running
    let l:command = copy(get(g:, 'webpreview_command', s:command))
    if !executable(l:command[0])
      call webpreview#notify('PREVIEW UNAVAILABLE', ['Executable not found: '.l:command[0]], 1)
      return 0
    endif
    if !empty(get(g:, 'webpreview_markdown_assets', ''))
      let l:command += ['--markdown-assets', expand(g:webpreview_markdown_assets)]
    endif
    let s:preview = {'buffer': bufnr('')}
    let s:preview.job = job_start(l:command + ['--markdown', expand('%:p'), '--serve',
          \ '--url-host', get(g:, 'webpreview_host', '127.0.0.1')], {
          \ 'in_io': 'pipe', 'out_cb': function('s:Output', [s:preview]),
          \ 'err_cb': function('s:Error', [s:preview]), 'exit_cb': function('s:Exited', [s:preview])})
  else
    call timer_stop(get(s:preview, 'timer', -1))
    let s:preview.buffer = bufnr('')
    call s:Source()
    call s:Cursor()
    call s:Send({'event': 'open'})
  endif
  augroup webpreview_markdown_buffer
    autocmd!
    execute 'autocmd TextChanged,TextChangedI,BufFilePost,FileChangedShellPost <buffer='.s:preview.buffer.'> call <SID>Schedule()'
    execute 'autocmd CursorMoved,CursorMovedI <buffer='.s:preview.buffer.'> call <SID>Cursor()'
    execute 'autocmd BufWipeout <buffer='.s:preview.buffer.'> call webpreview#markdown#stop()'
  augroup END
  return job_status(s:preview.job) !=# 'fail'
endfunction

function! webpreview#markdown#stop() abort
  let l:preview = s:preview
  let s:preview = {}
  call timer_stop(get(l:preview, 'timer', -1))
  augroup webpreview_markdown_buffer
    autocmd!
  augroup END
  if has_key(l:preview, 'job') && job_status(l:preview.job) ==# 'run'
    call ch_close_in(job_getchannel(l:preview.job))
  endif
endfunction

function! webpreview#markdown#url() abort
  return get(s:preview, 'url', '')
endfunction

augroup webpreview_markdown
  autocmd!
  autocmd SafeState * call <SID>Resume()
  autocmd VimLeavePre * call webpreview#markdown#stop()
augroup END
