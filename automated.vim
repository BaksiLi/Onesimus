" System detection
if has('win32') || has('win64') || has('win95') || has('win16')
  let g:asc_uname = 'windows'
elseif has('win32unix')
  let g:asc_uname = 'cygwin'
elseif has('mac') || has('macunix')
  let g:asc_uname = 'darwin'
elseif has('linux')
  let g:asc_uname = 'linux'
elseif has('bsd')
  let g:asc_uname = 'bsd'
elseif has('unix')
  let g:asc_uname = 'posix'
else
  let g:asc_uname = 'posix'
endif

" Bootstrap vim-plug before any Plug declarations are evaluated.  Keep the
" location configurable, but default to Vim's conventional autoload path.
let g:onesimus_bootstrap_ready = 0
let s:plug_bootstrapped = 0
if !filereadable(g:onesimus_vim_plug)
  if !executable('curl')
    echoerr 'Onesimus needs curl to install vim-plug: '.g:onesimus_vim_plug
    finish
  endif
  call mkdir(fnamemodify(g:onesimus_vim_plug, ':h'), 'p')
  let s:plug_url =
        \ 'https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  let s:plug_download = g:onesimus_vim_plug.'.'.getpid().'.tmp'
  silent! call delete(s:plug_download)
  call system('curl -fL --silent --show-error '
        \ .'--connect-timeout 10 --max-time 120 -o '
        \ .shellescape(s:plug_download).' '.shellescape(s:plug_url))
  let s:download_failed = v:shell_error != 0
        \ || !filereadable(s:plug_download)
  if !s:download_failed && rename(s:plug_download, g:onesimus_vim_plug) != 0
    let s:download_failed = !filereadable(g:onesimus_vim_plug)
  endif
  silent! call delete(s:plug_download)
  if s:download_failed && !filereadable(g:onesimus_vim_plug)
    echoerr 'Onesimus could not install vim-plug; check the network and retry.'
    finish
  endif
  let s:plug_bootstrapped = 1
endif

if !exists('*plug#begin')
  execute 'source '.fnameescape(g:onesimus_vim_plug)
endif
if !exists('*plug#begin')
  echoerr 'Onesimus could not load vim-plug: '.g:onesimus_vim_plug
  finish
endif
let g:onesimus_bootstrap_ready = 1

" A manually triggered VimEnter can let the timer run while Vim still reports
" vim_starting.  In that narrow case the reload below sources this file again;
" do not redefine a callback while it is on the call stack.
if !exists('*s:FinishBootstrap')
  function! s:FinishBootstrap(timer) abort
    let l:failed = &filetype ==# 'vim-plug' && search('^x', 'nw') > 0
    let l:missing = filter(values(copy(get(g:, 'plugs', {}))),
          \ 'has_key(v:val, ''uri'') && !isdirectory(get(v:val, ''dir'', ''''))')
    if l:failed || !empty(l:missing)
      let g:onesimus_bootstrap_pending = 0
      echohl WarningMsg
      echomsg 'Onesimus plugin installation is incomplete; review the plugin window and retry there.'
      echohl None
      return
    endif

    " PlugInstall runs during VimEnter.  Reloading immediately would replace
    " later VimEnter handlers before they have fired, including Onesimus Home.
    " A zero-delay timer runs after startup, when vim-plug can also source the
    " plugin scripts it has just installed.
    if &filetype ==# 'vim-plug' && bufname() =~# '^\[Plugins\]'
      silent! close
    endif
    let g:onesimus_bootstrap_pending = 0
    execute 'source '.fnameescape($MYVIMDOT)
    if exists('*OnesimusMaybeHome')
      call OnesimusMaybeHome()
    endif
  endfunction
endif

if s:plug_bootstrapped && !get(g:, 'onesimus_installing', 0)
  let g:onesimus_bootstrap_pending = 1
  augroup onesimus_bootstrap_plugins
    autocmd!
    autocmd VimEnter * ++once PlugInstall --sync
          \ | call timer_start(0, function('<SID>FinishBootstrap'))
  augroup END
endif
" TODO: detect if the dependency are installed
" Install nodejs and yarn if not installed; use shell script?
"   https://gist.github.com/JamieMason/4761049
" download skim if none for tex; download vint

" Recursive source function
function! s:source_all(dir)
  for l:name in sort(readdir(a:dir))
    let l:path = a:dir.'/'.l:name
    if l:name =~# '\.vim$' && getftype(l:path) ==# 'file'
      execute 'source '.fnameescape(l:path)
    endif
  endfor
endfunction
command! -nargs=1 -bar SourceAll  call s:source_all(<args>)

function! PlugInstalled(name) abort
  return has_key(get(g:, 'plugs', {}), a:name)
        \ && isdirectory(get(g:plugs[a:name], 'dir', ''))
endfunction

" Keep reload outside functions sourced from functions/*.vim.  Otherwise the
" active function would redefine itself halfway through :source (E127).
function! OnesimusReloadConfig() abort
  if !filereadable($MYVIMDOT)
    echohl ErrorMsg
    echomsg 'Onesimus configuration not found: '.$MYVIMDOT
    echohl None
    return
  endif
  if exists('*OnesimusTrack')
    call OnesimusTrack('meta.reload')
  endif
  execute 'source '.fnameescape($MYVIMDOT)
  echomsg 'Onesimus configuration reloaded.'
endfunction

" Some plugins moved GitHub owners without changing their vim-plug directory
" names.  vim-plug treats that as a URI conflict, so migrate only exact known
" legacy remotes before plugin declarations are read.
function! s:MigratePluginOrigin(directory, old, new) abort
  let l:dir = g:onesimus_plugin_home.'/'.a:directory
  let l:config = l:dir.'/.git/config'
  if !executable('git') || !filereadable(l:config)
    return
  endif

  let l:origin = ''
  let l:in_origin = 0
  for l:line in readfile(l:config)
    if l:line =~# '^\s*\['
      let l:in_origin = l:line =~? '^\s*\[\s*remote\s\+"origin"\s*\]\s*$'
    elseif l:in_origin && l:line =~? '^\s*url\s*='
      let l:origin = substitute(l:line, '^\s*url\s*=\s*', '', '')
      break
    endif
  endfor

  let l:legacy = [
        \ 'https://github.com/'.a:old,
        \ 'https://github.com/'.a:old.'.git',
        \ 'git@github.com:'.a:old,
        \ 'git@github.com:'.a:old.'.git',
        \ ]
  if index(l:legacy, l:origin) >= 0
    call system('git -C '.shellescape(l:dir).' remote set-url origin '
          \ .shellescape('https://github.com/'.a:new.'.git'))
  endif
endfunction
call s:MigratePluginOrigin('ale', 'w0rp/ale', 'dense-analysis/ale')
call s:MigratePluginOrigin('nerdtree', 'scrooloose/nerdtree',
      \ 'preservim/nerdtree')

" Configuration
" cf. https://github.com/skywind3000/vim/blob/master/bundle.vim
