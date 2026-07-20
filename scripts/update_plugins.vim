" Non-interactive plugin reconciliation used by install.sh --update.
" The updater owns this Vim process, so failing with :cquit is preferable to
" leaving a core/plugin mismatch hidden behind a successful shell status.

set nomore

function! s:Report(status, lines) abort
  if empty($ONESIMUS_UPDATE_REPORT)
    return
  endif
  call writefile([a:status] + a:lines, $ONESIMUS_UPDATE_REPORT)
endfunction

if !exists(':PlugUpdate')
  call s:Report('ERROR', ['vim-plug did not define :PlugUpdate'])
  cquit 31
endif

" These native-artifact hooks are intentionally synchronous strings.  Unlike
" the old funcref hooks, vim-plug puts lazy plugins on 'runtimepath' before a
" colon command and can report a build failure in its update buffer.  Keep the
" hooks here: vim-plug knows exactly which checkout changed and therefore
" rebuilds an artifact only when its source revision changed.  The explicit
" reconciliation below covers a missing artifact in an unchanged checkout.

try
  " vim-plug upgrades itself transactionally and keeps the old copy as
  " plug.vim.old.  A network failure here does not prevent the installed
  " manager from reconciling plugins below.
  if exists(':PlugUpgrade')
    silent! PlugUpgrade
  endif
  PlugUpdate --sync
catch
  call s:Report('ERROR', [v:exception])
  cquit 32
endtry

function! s:UpdateErrors() abort
  let l:lines = getline(1, '$')
  let l:errors = []
  let l:index = 0
  while l:index < len(l:lines)
    if l:lines[l:index] !~# '^x'
      let l:index += 1
      continue
    endif
    call add(l:errors, l:lines[l:index])
    let l:index += 1
    while l:index < len(l:lines) && l:lines[l:index] =~# '^\s'
      call add(l:errors, l:lines[l:index])
      let l:index += 1
    endwhile
  endwhile
  return l:errors
endfunction

let s:errors = s:UpdateErrors()

function! s:PluginDir(name) abort
  return get(get(get(g:, 'plugs', {}), a:name, {}), 'dir', '')
endfunction

function! s:ReconcileClap(errors) abort
  let l:dir = s:PluginDir('vim-clap')
  if empty(l:dir) || !isdirectory(l:dir)
    return
  endif
  let l:binary = l:dir.'/bin/maple'.(has('win32') ? '.exe' : '')
  if executable(l:binary)
    return
  endif
  let l:command = has('win32')
        \ ? 'powershell -ExecutionPolicy ByPass -File '.shellescape(l:dir.'/install.ps1')
        \ : 'cd '.shellescape(l:dir).' && ./install.sh'
  let l:output = system(l:command.' 2>&1')
  if v:shell_error || !executable(l:binary)
    let l:lines = split(l:output, "\n")
    let l:detail = empty(l:lines) ? 'installer produced no output'
          \ : substitute(l:lines[0], '\r$', '', '')
    call add(a:errors, 'vim-clap build: '.l:detail)
  endif
endfunction

function! s:ReconcileMarkdownPreview(errors) abort
  let l:dir = s:PluginDir('markdown-preview.nvim')
  if empty(l:dir)
    return
  endif
  try
    let l:manifest = l:dir.'/package.json'
    if !filereadable(l:manifest)
      throw 'package.json is missing'
    endif
    let l:package = json_decode(join(readfile(l:manifest), "\n"))
    if type(l:package) != type({})
          \ || type(get(l:package, 'version', 0)) != type('')
          \ || empty(trim(l:package.version))
      throw 'package.json has no usable version'
    endif
    let l:expected = trim(l:package.version)

    call plug#load('markdown-preview.nvim')
    " Autoload functions intentionally do not make exists('*name#func') true
    " before their first call; invoke them and let Vim resolve runtimepath.
    silent call mkdp#util#install_sync(v:true)
    let l:actual = trim(mkdp#util#pre_build_version())
    if empty(l:actual)
      throw 'preview binary is unavailable after installation'
    endif
    if l:actual !=# l:expected
      throw printf('preview binary version mismatch: expected %s, got %s',
            \ l:expected, l:actual)
    endif
  catch
    call add(a:errors, 'markdown-preview.nvim build: '.v:exception)
  endtry
endfunction

function! s:ReconcileJieba(errors) abort
  let l:dir = s:PluginDir('jieba.vim')
  if empty(l:dir) || !has('python3')
    return
  endif
  let l:binaries = glob(l:dir.'/pythonx/jieba_vim/jieba_vim_rs.*', 0, 1)
  call filter(l:binaries,
        \ 'v:val =~# ''\.\%(so\|dylib\|dll\|pyd\)$''')
  if !empty(l:binaries)
    return
  endif
  try
    call OnesimusJiebaInstall()
  catch
    call add(a:errors, v:exception)
  endtry
endfunction

call s:ReconcileClap(s:errors)
call s:ReconcileMarkdownPreview(s:errors)
call s:ReconcileJieba(s:errors)

let s:missing = []
for [s:name, s:spec] in items(get(g:, 'plugs', {}))
  if has_key(s:spec, 'uri') && !isdirectory(get(s:spec, 'dir', ''))
    call add(s:missing, 'missing plugin: '.s:name)
  endif
endfor

if !empty(s:errors) || !empty(s:missing)
  call s:Report('ERROR', s:errors + s:missing)
  cquit 33
endif

call s:Report('OK', [printf('%d plugins synchronized', len(get(g:, 'plugs', {})))])
qa!
