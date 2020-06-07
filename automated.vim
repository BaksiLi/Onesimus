" System detection
if has('win32') || has('win64') || has('win95') || has('win16')
  let g:asc_uname = 'windows'
elseif has('win32unix')
  let g:asc_uname = 'cygwin'
elseif has('unix') && (has('mac') || has('macunix'))
  let g:asc_uname = 'darwin'
elseif has('unix')
  let s:uname = substitute(system("uname"), '\s*\n$', '', 'g')
  if v:shell_error == 0 && match(s:uname, 'Linux') >= 0
    let g:asc_uname = 'linux'
  elseif v:shell_error == 0 && match(s:uname, 'FreeBSD') >= 0
    let g:asc_uname = 'freebsd'
  elseif v:shell_error == 0 && match(s:uname, 'Darwin') >= 0
    let g:asc_uname = 'darwin'
  else
    let g:asc_uname = 'posix'
  endif
else
  let g:asc_uname = 'posix'
endif

" Download vim-plug automatically 
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | so $MYVIMRC
endif
" TODO: detect if the dependency are installed
" Install nodejs and yarn if not installed; use shell script?
"   https://gist.github.com/JamieMason/4761049
" download skim if none for tex; download vint

" Recursive source function
function! s:source_all(dir)
  for f in glob(a:dir.'/*.vim', 0, 1)
    if f !~? 'test_'  " if not a test file
      exec 'so' f
    endif
  endfor
endfunction
command! -nargs=1 -bar SourceAll  call s:source_all(<args>)

" Vim-plug Cond helper function
function! Cond(cond, ...)
  let opts = get(a:000, 0, {})
  return a:cond ? opts : extend(opts, { 'on': [], 'for': [] })
endfunction

function! PlugLoaded(name)
  return (
    \ has_key(g:plugs, a:name) &&
    \ isdirectory(g:plugs[a:name].dir) &&
    \ stridx(&rtp, g:plugs[a:name].dir) >= 0)
endfunction

" Configuration
" cf. https://github.com/skywind3000/vim/blob/master/bundle.vim
