" The distribution's reviewed revisions; personal declarations load afterward.
let s:lock = json_decode(join(readfile($VIMRCDIR.'/plugins.lock.json'), "\n"))
if type(s:lock) != v:t_dict || get(s:lock, 'version', 0) != 1
      \ || type(get(s:lock, 'plugins', 0)) != v:t_dict
  throw 'Onesimus: invalid plugins.lock.json'
endif

function! s:LockedOptions(repo, options) abort
  let l:options = copy(a:options)
  let l:name = get(l:options, 'as', fnamemodify(a:repo, ':t'))
  let l:pin = get(s:lock.plugins, l:name, {})
  if get(l:pin, 'repository', '') ==# a:repo
    let l:commit = get(l:pin, 'commit', '')
    if type(l:commit) != v:t_string || l:commit !~# '^\x\{40}$'
      throw 'Onesimus: invalid plugin revision for '.l:name
    endif
    let l:options.commit = l:commit
  endif
  return l:options
endfunction

function! OnesimusLockPlugins() abort
  for [l:name, l:spec] in items(g:plugs)
    if !has_key(l:spec, 'uri') | continue | endif
    let l:repo = substitute(l:spec.uri, '^.*github.com/', '', '')
    let l:repo = substitute(l:repo, '\.git$', '', '')
    if !has_key(s:lock.plugins, l:name)
      throw 'Onesimus: missing plugin revision for '.l:name
    endif
    if get(s:lock.plugins[l:name], 'repository', '') !=# l:repo
      throw 'Onesimus: plugin lock source differs for '.l:name
    endif
    call extend(l:spec, s:LockedOptions(l:repo, {'as': l:name}))
  endfor
endfunction

" Optional plugins use the same pins. A local override deliberately leaves its
" checkout and build under the developer's control; updates never checkout it.
function! OnesimusPlugin(repo, ...) abort
  let l:options = copy(get(a:000, 0, {}))
  let l:name = get(l:options, 'as', fnamemodify(a:repo, ':t'))
  let l:local = get(get(g:, 'onesimus_plugin_overrides', {}), l:name, '')
  if !empty(l:local)
    let l:local = fnamemodify(expand(l:local), ':p')
    if !isdirectory(l:local)
      throw 'Onesimus: local plugin checkout not found: '.l:local
    endif
    " Local projects build explicitly; do not inherit a remote update hook.
    for l:key in ['commit', 'tag', 'branch', 'do']
      if has_key(l:options, l:key) | call remove(l:options, l:key) | endif
    endfor
    let l:options.as = l:name
    return call('plug#', [l:local, l:options])
  endif
  if !has_key(l:options, 'commit') && !has_key(l:options, 'tag')
    let l:options = s:LockedOptions(a:repo, l:options)
  endif
  return call('plug#', [a:repo, l:options])
endfunction
