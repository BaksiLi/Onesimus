" Capture actual installed revisions, including drift from the declared lock.
" vim-plug's PlugSnapshot uses spec.commit when present, so it cannot capture
" that drift for locked plugins. Local checkouts are recorded, never reset.
function! OnesimusPluginSnapshot(...) abort
  let l:base = empty($XDG_STATE_HOME)
        \ ? expand('~/.local/state') : expand($XDG_STATE_HOME)
  let l:directory = l:base.'/onesimus/plugin-snapshots'
  let l:path = get(a:000, 0, '')
  if empty(l:path)
    call mkdir(l:directory, 'p', 0700)
    let l:path = l:directory.'/'.strftime('%Y%m%d-%H%M%S').'-'.getpid().'.vim'
    let l:suffix = 0
    while getftype(l:path) !=# ''
      let l:suffix += 1
      let l:path = l:directory.'/'.strftime('%Y%m%d-%H%M%S').'-'.getpid().'-'.l:suffix.'.vim'
    endwhile
  else
    let l:path = fnamemodify(expand(l:path), ':p')
    if getftype(l:path) !=# ''
      throw 'Onesimus: plugin snapshot already exists: '.l:path
    endif
  endif
  let l:lines = ['" Onesimus installed-plugin snapshot',
        \ '" Source in Vim with Onesimus loaded to restore remote revisions.',
        \ '" Local checkouts and uncommitted changes are not restored.', '']
  for l:name in sort(keys(get(g:, 'plugs', {})))
    let l:spec = g:plugs[l:name]
    if !isdirectory(l:spec.dir) | continue | endif
    let l:revision = trim(system('git -C '.shellescape(l:spec.dir).' rev-parse --verify HEAD 2>&1'))
    if v:shell_error || l:revision !~# '^\x\{40}$'
      throw 'Onesimus: cannot snapshot installed plugin: '.l:name
    endif
    let l:changes = system('git -C '.shellescape(l:spec.dir).' status --porcelain --untracked-files=no 2>&1')
    if v:shell_error
      throw 'Onesimus: cannot inspect plugin changes: '.l:name
    endif
    call add(l:lines, '" '.l:name.' '.l:revision
          \ .(empty(l:changes) ? '' : ' (tracked changes present)'))
    if has_key(l:spec, 'uri')
      " Match the source too: a later personal fork must not receive this pin.
      call extend(l:lines, [
            \ 'if get(get(g:plugs, '.string(l:name).', {}), ''uri'', '''') ==# '.string(l:spec.uri),
            \ '  let g:plugs['.string(l:name).'].commit = '.string(l:revision),
            \ 'endif'])
    else
      call add(l:lines, '" Local checkout: '.string(l:spec.dir))
    endif
  endfor
  call extend(l:lines, ['', 'PlugUpdate --sync'])
  if writefile(l:lines, l:path) != 0
    throw 'Onesimus: cannot write plugin snapshot: '.l:path
  endif
  call setfperm(l:path, 'rw-------')
  let g:onesimus_last_plugin_snapshot = l:path
  return l:path
endfunction

function! s:Snapshot(path) abort
  echomsg 'Plugin snapshot: '.OnesimusPluginSnapshot(a:path)
endfunction
command! -nargs=? -complete=file OnesimusPluginSnapshot call <SID>Snapshot(<q-args>)
