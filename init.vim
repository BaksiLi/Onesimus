" Project: Onesimos Vim
" Maintainer: BaksiLi
" Version: 0.1.2
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

"--------------------------------------------------------------
" Automated Installations
"------------------------------------------------------------
if has('vim_starting')
  set encoding=utf-8
  scriptencoding utf-8
  set nocompatible  " vim_starting prevents this to be reloaded

  if filereadable(glob($VIMRCDIR.'/automated.vim'))
    so $VIMRCDIR/automated.vim
  endif
endif

" g:asc_uname

"--------------------------------------------------------------
" General Configurations and Keymaps
"--------------------------------------------------------------
" Set alternative leader key (default: '\')
let mapleader = '\'

" ------ Meta ------
" Edit dotfile
nmap <leader>ed :vsplit $MYVIMDOT<cr>
" Source dotfile
nmap <leader>sd :source $MYVIMRC<cr>
" Help document
nnoremap <leader>h :view +let\ &l:modifiable=0 $VIMRCDIR/README.md<cr>
" nnoremap <leader>H :execute ':help ' . expand('<cword>')<cr>

syntax on   " highlight syntax
filetype plugin indent on  " for vimtex, why indent?

set fileencodings=utf-8,12,shift-jis,gbk,big
set magic
set nomodeline  " for safety

set autochdir  " always always change to the current file's directory
set scrolloff=4

" ------ Editing ------
set ruler
set number        " line numbering
" key for toggle relative numbering
nmap <leader>tr :set rnu!<cr>
set cursorline

" ------ Search ------
set hlsearch      " highlight search results
set incsearch     " real time search
set showmatch
set ignorecase

set nobackup
set nowritebackup
set autoread      " if file is edited outside, reload automatically
set confirm       " confirm when read-only

set cmdheight=2   " Better message
" Shorter updatetime for CursorHold & CursorHoldI
set updatetime=300
set timeoutlen=750

" Manual folding
set foldmethod=manual
"nnoremap <space> @=((foldclosed(line('.')<0)?'zc':'zo'))<CR>

" ------ Indentation ------
set autoindent           " indent based on the previous line
set smartindent          " optional
set sidescroll=10
set backspace=2          " indent,eol,start

augroup set_indents
  set expandtab          " tab to spaces
    \ tabstop=4
    \ shiftwidth=4
    \ softtabstop=4
  au Filetype python set
    \ textwidth=79
  " use condition to set *.js, *.html, *.css
  "    \ set tabstop=2
  "    \ set softtabstop=2
  "    \ set shiftwidth=2
  au Filetype tex set
    \ tabstop=4
    \ concealcursor-=n   " overwritten by indentLine
    \ let g:indentLine_concealcursor = 'ic'
  au Filetype vim,snippets set
    \ tabstop=2
    \ shiftwidth=2
  au Filetype yaml set
    \ noexpandtab
    \ tabstop=4
    \ shiftwidth=2
augroup END

augroup lisp_behaviour
  autocmd FileType lisp,emacs,scheme RainbowToggle
augroup end

" ------ Keymaps ------
" NB Some keymaps are loaded later
" Fast split navigations
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

" Enforcing HJKL-style
" NB this will cause problem to some plugins 
" map <Up> <Nop>
map <Up> :echoe 'Use HJKL (k)!'<cr>k
map <Down> :echoe 'Use HJKL (j)!'<cr>j
map <Left> :echoe 'Use HJKL (h)!'<cr>h
map <Right> :echoe 'Use HJKL (l)!'<cr>l

" Alternative to <esc>
inoremap lkj <esc>

" Buffer move
nnoremap ]b :bnext<cr>
nnoremap [b :bprev<cr>

"--------------------------------------------------------------
" Plugins
"--------------------------------------------------------------
call plug#begin('~/.vim/bundle')

" ------ IDE and UI features ------
Plug 'mhinz/vim-startify'
Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }
Plug 'majutsushi/tagbar', {'on': 'TagbarToggle'}
Plug 'liuchengxu/vim-which-key'

" Assync Run (Vim 8?)
Plug 'skywind3000/asyncrun.vim'
" Plug 'skywind3000/asynctasks.vim'  " this is good but a bit heavy

" Stats
" Plug  'wakatime/vim-wakatime'

" Fuzzy finder
Plug 'Yggdroot/LeaderF', { 'do': '.\install.bat' }

" ------ Colour Schemes ------
" TODO: Airline remove battery, add pyenv, cf :h statusline
"   if font not compatible, use other seperator
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

Plug 'morhetz/gruvbox'
Plug 'junegunn/seoul256.vim' 
Plug 'arcticicestudio/nord-vim'
Plug 'sickill/vim-monokai'

" ------ Git Support ------
Plug 'tpope/vim-fugitive'
Plug 'mhinz/vim-signify'  "faster than vim-gitgutter
" Plug 'Xuyuanp/nerdtree-git-plugin'
" Plug 'junegunn/vim-emoji'
"   command! -range EmojiReplace <line1>,<line2>s/:\([^:]\+\):/\=emoji#for(submatch(1), submatch(0))/g

" ------ Language Server Client ------
Plug 'neoclide/coc.nvim', {'do': './install.sh nightly'}

" Linter and Fixer
Plug 'w0rp/ale'  " Config 'ALELintFix.vim'
" Work with coc LSC

" ------ Lang-specific Plugs ------
" Markdown
Plug 'gabrielelana/vim-markdown' , { 'for': 'markdown'}
Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app & yarn install' , 'for': 'markdown' }
Plug 'BaksiLi/vim-markdown-toc', { 'for': 'markdown' }  " originally 'mzlogin/vim-markdown-toc'
" Markdown mappings?  like :onoremap ih :<c-u>exec 'normal! ?^==\\+$\r:nohlsearch\rkvg_'<cr>

" TeX
" requires latexmk, `sudo tlmgr install latexmk`; coc-vimtex
Plug 'lervag/vimtex', { 'for': 'tex' }
Plug 'KeitaNakamura/tex-conceal.vim', { 'for': 'tex' }

" Swift 
Plug 'bumaociyuan/vim-swift', { 'for': 'swift' }  " syntax (fork from official)

" TODO: coc-settings.json
" coc-tabnine coclist?
" coc-json, coc-html
" coc-python

" Haskell
" https://github.com/jaspervdj/stylish-haskell
Plug 'neovimhaskell/haskell-vim', { 'for': 'haskell'}
Plug 'chrisdone/hindent', { 'for': 'haskell'}

" Agda
" ...

" ------ Editing ------
" Parentheses helper
Plug 'tpope/vim-surround'
" Reapeating plugin
Plug 'tpope/vim-repeat'
" Comment operator (gc)
Plug 'tpope/vim-commentary'
" Tabular
Plug 'godlygeek/tabular'

" vim-multiple-cursors  " Multi-cursor is poisonous

" Auxiliary indicator
Plug 'Yggdroot/indentLine'
Plug 'luochen1990/rainbow', { 'on': 'RainbowToggle' }
  let g:rainbow_active = 0

" Snippets
Plug 'SirVer/ultisnips'
":CocInstall coc-snippets
" Plug 'honza/vim-snippets'

" ------ Miscellanous ------
" Plug 'jamessan/vim-gnupg'

" ------ Initialze Plugin System ------
call plug#end()

" Load config files
SourceAll $VIMRCDIR.'/plugconf'

" AsyncRun for fugitive
if &runtimepath =~ 'asyncrun'
  command! -bang -nargs=* -complete=file Make AsyncRun -program=make @ <args>
endif

" GUI settings
set termguicolors  " need +termguicolors
if has('gui_running')
  colorscheme nord
else
  "let g:gruvbox_contrast_dark = 'medium'
  let g:gruvbox_improved_warnings = 1
  set background=dark
  colorscheme gruvbox
  let g:airline_theme = 'gruvbox'
endif

" Change cursor under different modes (for iTerm2 only)
if exists('$TMUX')
  let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
  let &t_SR = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=2\x7\<Esc>\\"
  let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
else
  let &t_SI = "\<Esc>]50;CursorShape=1\x7"
  let &t_SR = "\<Esc>]50;CursorShape=2\x7"
  let &t_EI = "\<Esc>]50;CursorShape=0\x7"
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

" File Header
au BufNewFile *.cpp,*.[ch],*.sh,*.rb,*.java,*.py,*.ts exec ":call SetHeader()"

" Functional Keys
nmap <F2> :TagbarToggle<cr>
nmap <F3> :NERDTreeToggle<cr>
nmap <F4> :OpenREPL<cr>
nmap <F5> :CompileRun<cr>
nmap <F6> :ALEFix<cr>

" TODO: more ctags into a fn
nnoremap <leader>et command! MakeTags !ctags -R .<cr>

" TODO: enable wordprocessingmode for certain filetypes
" :autocmd FileType javascript nnoremap <buffer> <localleader>c I//<esc>

" Colour Column
" exclude latex
" The line length should be limited to 72 characters, 79 at max.
" see https://www.python.org/dev/peps/pep-0008/#maximum-line-length.
" highlight OverLength ctermbg=red ctermfg=white guibg=#592929
" match OverLength /\%280v.\+/
" set colorcolumn=+1  " fancier?
