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

" Download vim-plug
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" TODO: let user to choose the package
" https://github.com/skywind3000/vim/blob/master/bundle.vim

" TODO: detect if the dependency are installed
" Install nodejs and yarn if not installed
"   maybe use bash?
"   https://gist.github.com/JamieMason/4761049
" download skim if none for tex
" download vint


" TODO: backup to designated folder (by python or something)
"   check if anything changed, git backup

" Learn from:
" " Load dein.
" let s:dein_dir = finddir('dein.vim', '.;')
" if s:dein_dir != '' || &runtimepath !~ '/dein.vim'
"   if s:dein_dir == '' && &runtimepath !~ '/dein.vim'
"     let s:dein_dir = expand('$CONFIG/nvim')
"           \. '/repos/github.com/Shougo/dein.vim'
"     if !isdirectory(s:dein_dir)
"       echomsg 'Download dein plugin management wait a moment'
"       execute '!git clone https://github.com/Shougo/dein.vim' s:dein_dir
"     endif
"   endif
"   execute 'set runtimepath^=' . substitute(
"         \ fnamemodify(s:dein_dir, ':p') , '/$', '', '')
" endif
