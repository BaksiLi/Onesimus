" Project: Onesimus Vim
" Maintainer: BaksiLi
" Version: 0.2.0
"--------------------------------------------------------------
" Menu
"--------------------------------------------------------------
" let $VIMRCDIR = $BASEDIR.'/vimrc'
" let $MYVIMDOT = $VIMRCDIR.'/init.vim'
"
" 1 Automated Installations
"       automated.vim
" 2 General Configurations
"       NA
" 3 Plugin Configurations
"       plugconf/*.vim
" 4 Custom Functions and Keys
"       functions/*.vim

" The configuration is its own source of truth.  A loader may override the
" root for an embedded installation, but invoking `vim -Nu /path/init.vim`
" must work without any surrounding shell state.
let s:onesimus_root = fnamemodify(resolve(expand('<sfile>:p')), ':h')
if empty($VIMRCDIR)
  let $VIMRCDIR = s:onesimus_root
endif
if empty($MYVIMDOT)
  let $MYVIMDOT = $VIMRCDIR.'/init.vim'
endif

if v:version < 802 || !has('job') || !has('channel') || !has('timers')
  echoerr 'Onesimus requires Vim 8.2 or newer with +job, +channel, and +timers.'
  finish
endif

let g:onesimus_plugin_home = fnamemodify(
      \ get(g:, 'onesimus_plugin_home',
      \   empty($ONESIMUS_PLUGIN_HOME) ? '~/.vim/bundle'
      \                                 : $ONESIMUS_PLUGIN_HOME), ':p')
let g:onesimus_vim_plug = fnamemodify(
      \ get(g:, 'onesimus_vim_plug',
      \   empty($ONESIMUS_VIM_PLUG) ? '~/.vim/autoload/plug.vim'
      \                             : $ONESIMUS_VIM_PLUG), ':p')

"--------------------------------------------------------------
" Automated Installations
"------------------------------------------------------------
if has('vim_starting')
  set encoding=utf-8
  scriptencoding utf-8

  if &compatible
    set nocompatible  " vim_starting prevents this to be reloaded
  endif

  if filereadable($VIMRCDIR.'/automated.vim')
    execute 'source '.fnameescape($VIMRCDIR.'/automated.vim')
  endif
endif

if !get(g:, 'onesimus_bootstrap_ready', 0)
  finish
endif

let g:onesimus_version = '0.2.0'

" g:asc_uname
" TODO: dependencies for lua, python

"--------------------------------------------------------------
" General Configurations and Keymaps
"--------------------------------------------------------------
" Set alternative leader key (default: '\')
let mapleader = '\'
let maplocalleader = ','

" ------ Meta ------
" Stable Onesimus entrypoints are defined after plugin setup.
nnoremap <silent> <leader>ed :OnesimusEditConfig<cr>
nnoremap <silent> <leader>sd :OnesimusReload<cr>
nnoremap <silent> <leader>h :OnesimusHelp<cr>
nnoremap <silent> <leader>? :OnesimusHelp<cr>
nnoremap <silent> <leader>oh :OnesimusHome<cr>
nnoremap <silent> <leader>os :OnesimusStats<cr>
nnoremap <silent> <leader>. :call OnesimusGuide('context')<cr>
nnoremap <silent> <leader> :OnesimusGuide<cr>
" nnoremap <leader>H :execute ':help ' . expand('<cword>')<cr>

" Prefer Unicode, but keep common Traditional/Simplified Chinese and Japanese
" encodings readable when opening older notes.
set fileencodings=ucs-bom,utf-8,big5,gb18030,cp932,euc-jp,default,latin1
set magic
set nomodeline  " for safety

" Keep one project root for ALE, Clap, Fugitive, and :make.  Start Vim from a
" project directory (or use :cd) instead of changing CWD for every buffer.
set noautochdir
set scrolloff=4

" ------ Editing ------
set ruler
set number        " line numbering
" key for toggle relative numbering
nnoremap <silent> <leader>tr :OnesimusToggleRelativeNumber<cr>
nnoremap <silent> <leader>ti :OnesimusIndentToggle<cr>
nnoremap <silent> <leader>tp :OnesimusParenthesisToggle<cr>
nnoremap <silent> <leader>tw :WPModeToggle<cr>
nnoremap <silent> <leader>tb :ToggleBackground<cr>
set cursorline
set hidden        " switch buffers without forcing an intermediate write
set splitbelow
set splitright
set display+=lastline
set list          " native indentation guides are configured per buffer

" ------ Search ------
set hlsearch      " highlight search results
set incsearch     " real time search
set showmatch
set ignorecase
" set smartcase

set nobackup
set nowritebackup
set autoread      " if file is edited outside, reload automatically
set confirm       " confirm when read-only

set cmdheight=1
set sidescroll=10
" Shorter updatetime for CursorHold & CursorHoldI
set updatetime=300
set timeoutlen=750

" Manual folding
set foldmethod=manual
set nofoldenable
"nnoremap <space> @=((foldclosed(line('.')<0)?'zc':'zo'))<CR>

" ------ Indentation ------
set autoindent           " indent based on the previous line
set nosmartindent        " filetype indent scripts know more than C heuristics
set backspace=indent,eol,start

" Replace it with EditorConfig?
set expandtab  " tab to spaces
set tabstop=2
set shiftwidth=2
set softtabstop=2

augroup set_indents
  autocmd!
  au Filetype tex setlocal
    \ concealcursor-=n
    \ conceallevel=1
  au Filetype yaml setlocal
    \ expandtab
    \ tabstop=4
    \ shiftwidth=2
  au FileType json setlocal
    \ conceallevel=0
  au FileType go setlocal
    \ noexpandtab
    \ shiftwidth=4
    \ softtabstop=4
    \ tabstop=4
augroup END

augroup lisp_behaviour
  autocmd!
  autocmd FileType * call OnesimusConfigureParentheses()
augroup end

" ------ Keymaps ------
" NB Some keymaps are loaded later
" Fast split navigations
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

" Stable fuzzy-finder actions.  The wrapper explains how to install vim-clap
" instead of leaving a raw E492 when plugins have not been bootstrapped yet.
nnoremap <silent> <leader>ff :OnesimusClap files<cr>
nnoremap <silent> <leader>fb :OnesimusClap buffers<cr>
nnoremap <silent> <leader>ft :OnesimusClap tags<cr>
nnoremap <silent> <leader>fg :OnesimusClap git_files<cr>
nnoremap <silent> <leader>fw :OnesimusClap grep<cr>
nnoremap <silent> <leader>fm :OnesimusClap marks<cr>
nnoremap <silent> <leader>fh :OnesimusClap history<cr>
nnoremap <silent> <leader>fc :OnesimusClap command_history<cr>

" Keep the old HJKL nudge in Normal mode without stealing arrows from Visual,
" Select, or Operator-pending mode.  WarningMsg is advisory and does not raise
" an error that can abort a larger mapping or macro.
nnoremap <silent> <Up> :<C-U>echohl WarningMsg <Bar> echomsg 'Use k (up).' <Bar> echohl None<CR>
nnoremap <silent> <Down> :<C-U>echohl WarningMsg <Bar> echomsg 'Use j (down).' <Bar> echohl None<CR>
nnoremap <silent> <Left> :<C-U>echohl WarningMsg <Bar> echomsg 'Use h (left).' <Bar> echohl None<CR>
nnoremap <silent> <Right> :<C-U>echohl WarningMsg <Bar> echomsg 'Use l (right).' <Bar> echohl None<CR>

" Alternative to <esc>
inoremap lkj <esc>

" Buffer move
nnoremap ]b :bnext<cr>
nnoremap [b :bprev<cr>
" QuickFix move
nnoremap [c :cprevious<CR>
nnoremap ]c :cnext<CR>
" Tab move
" nmap <S-Tab> :tabprev<Return>
" nmap <Tab> :tabnext<Return>

nnoremap X $x

"--------------------------------------------------------------
" Plugins
"--------------------------------------------------------------
call plug#begin(g:onesimus_plugin_home)

" ------ IDE and UI features ------
" Vim 9.0.1799 and newer ship the same EditorConfig implementation as an
" optional package.  Keep older supported Vims coherent with one conditional
" fallback instead of asking each machine to install an external parser.
let s:onesimus_native_editorconfig =
      \ isdirectory($VIMRUNTIME.'/pack/dist/opt/editorconfig')
if !s:onesimus_native_editorconfig
  Plug 'editorconfig/editorconfig-vim', { 'tag': 'v1.2.1' }
endif

Plug 'mhinz/vim-startify'
Plug 'preservim/nerdtree', { 'on': 'NERDTreeToggle' }
" Plug 'majutsushi/tagbar', {'on': 'TagbarToggle'}
" Plug 't9md/vim-choosewin'

" Asynchronous tasks
Plug 'skywind3000/asyncrun.vim'
" Plug 'skywind3000/asynctasks.vim'  " this is good but a bit heavy

" Stats
" Plug 'dstein64/vim-startuptime'

" Fuzzy finder
let g:onesimus_clap_install = g:asc_uname ==# 'windows'
      \ ? 'powershell -ExecutionPolicy ByPass -File .\install.ps1'
      \ : './install.sh'
Plug 'liuchengxu/vim-clap', {
      \ 'on': 'Clap',
      \ 'do': g:onesimus_clap_install,
      \ }
unlet g:onesimus_clap_install

" ------ Colour Schemes ------
" TODO: Airline remove battery, add pyenv, cf :h statusline
"   if the font is not compatible, use another separator
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

Plug 'morhetz/gruvbox'
Plug 'junegunn/seoul256.vim'
Plug 'arcticicestudio/nord-vim'
Plug 'sickill/vim-monokai'

" ------ Git Support ------
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'
" Plug 'Xuyuanp/nerdtree-git-plugin'
" Plug 'junegunn/vim-emoji'
"   command! -range EmojiReplace <line1>,<line2>s/:\([^:]\+\):/\=emoji#for(submatch(1), submatch(0))/g


" ------ Language Server Client ------
" Snippets
Plug 'SirVer/ultisnips'
" Plug 'honza/vim-snippets'

" ALE is the sole LSP client, diagnostic UI, linter, and fixer.
Plug 'dense-analysis/ale'

" ------ Lang-specific Plugs ------
" Markdown
Plug 'iamcco/markdown-preview.nvim', {
      \ 'do': ':call mkdp#util#install_sync()',
      \ 'for': 'markdown',
      \ }
Plug 'BaksiLi/vim-markdown-toc', { 'for': 'markdown' }  " originally 'mzlogin/vim-markdown-toc'

" TeX
" requires latexmk, for example: `sudo tlmgr install latexmk`
Plug 'lervag/vimtex', { 'for': ['tex', 'bib'] }

" VimScript Reference
Plug 'tweekmonster/helpful.vim', { 'on': 'HelpfulVersion' }
Plug 'junegunn/vader.vim', { 'on': 'Vader' }

" Highlight not already covered by Vim's current runtime.
Plug 'BaksiLi/vim-applescript'
" Plug 'leafgarland/typescript-vim'
" Plug 'rust-lang/rust.vim'
" Plug 'jparise/vim-graphql'

" Web
Plug 'mattn/emmet-vim', { 'for': 'html' }

" Haskell
" https://github.com/jaspervdj/stylish-haskell
Plug 'neovimhaskell/haskell-vim', { 'for': 'haskell'}



" ------ Editing ------
" Parentheses helper
Plug 'tpope/vim-surround'
" Repeat plugin actions with .
Plug 'tpope/vim-repeat'
" Comment operator (gc)
Plug 'tpope/vim-commentary'
" Tabular
Plug 'godlygeek/tabular'

" Chinese word motions and text objects.  Keep the plugin out of Vim builds
" without +python3, and pin its native backend to a reproducible release.
if has('python3')
  let g:jieba_vim_keymap = 0
  Plug 'kkew3/jieba.vim', {
        \ 'tag': 'v2.1.1',
        \ 'on': [],
        \ 'do': ':call OnesimusJiebaInstall()',
        \ }
endif

" vim-multiple-cursors  " Multi-cursor is poisonous

" Improved increment <C-a>/<C-x>
Plug 'tpope/vim-speeddating'


" Undo Tree
" Plug 'mbbill/undotree'

" Auxiliary indicator
Plug 'luochen1990/rainbow', {
      \ 'on': ['RainbowToggle', 'RainbowToggleOn', 'RainbowToggleOff'],
      \ }
  let g:rainbow_active = 0  " default off

" Focus mode
Plug 'junegunn/goyo.vim', { 'on': 'Goyo' }
Plug 'junegunn/limelight.vim', { 'on': 'Limelight' }


" ------ Miscellaneous ------
" Plug 'jamessan/vim-gnupg'

" ------ Load Custom Plugins ------
if filereadable($VIMRCDIR.'/custom/plugins.vim')
  execute 'source '.fnameescape($VIMRCDIR.'/custom/plugins.vim')
endif

" ------ Initialize Plugin System ------
call plug#end()

" plug#end() enables syntax plus filetype plugins/indent exactly once, after
" the final runtimepath is known.

" Recent Vim runtimes ship EditorConfig as an optional native package.  Its
" stock VimEnter/BufNew handler expands <afile> even when no event filename
" exists (for example :new), so keep the package but drive it only for named,
" normal buffers.  This also prevents dashboards from producing E495.
function! s:ApplyEditorConfig() abort
  if &l:buftype !=# '' || empty(expand('%:p'))
    return
  endif
  silent EditorConfigReload
  " EditorConfig can change shiftwidth after the FileType event which first
  " built our native indentation markers.  Keep the visual period in lockstep
  " with the effective buffer settings, regardless of which provider supplied
  " them.
  if exists('*OnesimusConfigureIndentGuides')
    call OnesimusConfigureIndentGuides()
  endif
endfunction

augroup onesimus_editorconfig
  autocmd!
augroup END

if s:onesimus_native_editorconfig
  silent! packadd editorconfig
elseif PlugInstalled('editorconfig-vim')
  " Plugin scripts normally load after vimrc; source the fallback now so both
  " implementations follow the same lifecycle below.  Its load guard makes
  " Vim's later plugin pass harmless.
  silent! runtime plugin/editorconfig.vim
endif

if exists(':EditorConfigDisable')
  silent! EditorConfigDisable
  augroup onesimus_editorconfig
    autocmd!
    autocmd BufNewFile,BufReadPost,BufFilePost * call <SID>ApplyEditorConfig()
  augroup END
  call s:ApplyEditorConfig()
endif

" Load config files
SourceAll $VIMRCDIR.'/plugconf'

" AsyncRun for fugitive
if PlugInstalled('asyncrun.vim')
  command! -bang -nargs=* -complete=file Make AsyncRun -program=make @ <args>
endif

" GUI settings
if exists('+termguicolors')
  set termguicolors
endif
if has('gui_running')
  try
    colorscheme nord
  catch /^Vim\%((\a\+)\)\=:E185/
    colorscheme default
  endtry
else
  let g:gruvbox_improved_warnings = 1
  set background=dark
  try
    colorscheme gruvbox
    let g:airline_theme = 'gruvbox'
  catch /^Vim\%((\a\+)\)\=:E185/
    colorscheme default
  endtry
endif

" Change cursor under different modes (for iTerm2 only)
if exists('$TMUX')
  let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>[6 q\<Esc>\\"
  let &t_SR = "\<Esc>Ptmux;\<Esc>\<Esc>[4 q\<Esc>\\"
  let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>[2 q\<Esc>\\"
else
  let &t_SI = "\<Esc>[6 q"
  let &t_SR = "\<Esc>[4 q"
  let &t_EI = "\<Esc>[2 q"
endif
" TODO: if two tmux detected, set notermguicolors to avoid colour lost

" start a clientserver under terminal?
" if empty(v:servername) && exists('*remote_startserver')
" call remote_startserver('VIM')
" endif


"--------------------------------------------------------------
" Custom Functions
"--------------------------------------------------------------
" Load all functions
SourceAll $VIMRCDIR.'/functions'

" Functional Keys
nmap <silent> <F2> :OnesimusBufferSymbols<cr>
nmap <silent> <F3> :OnesimusTree<cr>
nmap <F4> :OpenREPL<cr>
nmap <F5> :CompileRun<cr>
nmap <silent> <F6> :OnesimusFormat<cr>

nnoremap <silent> <leader>et :OnesimusTags<cr>

" command W w !sudo tee % > /dev/null


" TODO: enable wordprocessingmode for certain filetypes
" :autocmd FileType javascript nnoremap <buffer> <localleader>c I//<esc>

" Colour Column
" exclude latex
" The line length should be limited to 72 characters, 79 at max.
" see https://www.python.org/dev/peps/pep-0008/#maximum-line-length.
" highlight OverLength ctermbg=red ctermfg=white guibg=#592929
" match OverLength /\%280v.\+/
" set colorcolumn=+1  " fancier?
