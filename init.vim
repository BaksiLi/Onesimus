" Project: Onesimos Vim
" Maintainer: BaksiLi
" Version: 0.1
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

" TODO:
" - general config first?
" - move plugin installs to a seperate file
" - let choose font

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
nmap <leader>r :set rnu!<cr>
set cursorline

" ------ Search ------
set hlsearch      " highlight search results
set incsearch     " real time search
set showmatch
set ignorecase

" coc setup: Some servers have issues with backup files
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
map <Up> :echo 'Use HJKL (k)!'<cr>k
map <Down> :echo 'Use HJKL (j)!'<cr>j
map <Left> :echo 'Use HJKL (h)!'<cr>h
map <Right> :echo 'Use HJKL (l)!'<cr>l

" Alternative to <esc>
inoremap lkj <esc>

"--------------------------------------------------------------
" Plugins
"--------------------------------------------------------------
call plug#begin('~/.vim/bundle')

" ------ IDE and UI features ------
Plug 'mhinz/vim-startify'
Plug 'scrooloose/nerdtree'
Plug 'majutsushi/tagbar'
Plug 'liuchengxu/vim-which-key'

" Assync Run (Vim 8?)
Plug 'skywind3000/asyncrun.vim'

" vim-minimap

" Fuzzy finder
Plug 'Yggdroot/LeaderF', { 'do': '.\install.bat' }

" ------ Colour Schemes ------
" TODO: Airline remove battery, add pyenv, cf :h statusline
"   if font not compatible, use other seperator
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'morhetz/gruvbox'
Plug 'endel/vim-github-colorscheme'

" ------ Git Support ------
Plug 'tpope/vim-fugitive'
Plug 'mhinz/vim-signify'  "faster than vim-gitgutter
Plug 'airblade/vim-gitgutter'
" Plug 'Xuyuanp/nerdtree-git-plugin'

" ------ Language Server Client ------
Plug 'neoclide/coc.nvim', {'do': './install.sh nightly'}
" CocInstall coc-tabnine coclist?

" Linter and Fixer
Plug 'w0rp/ale'  " Config 'ALELintFix.vim'
" Work with coc LSC

" ------ Lang-specific Plugs ------
" Markdown
Plug 'gabrielelana/vim-markdown'
Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app & yarn install'  }
Plug 'BaksiLi/vim-markdown-toc' " originally 'mzlogin/vim-markdown-toc'
" Markdown mappings?  like :onoremap ih :<c-u>exec 'normal! ?^==\\+$\r:nohlsearch\rkvg_'<cr>

" TeX
" requires latexmk, `sudo tlmgr install latexmk`
" coc-vimtex
Plug 'lervag/vimtex' " config avail
Plug 'KeitaNakamura/tex-conceal.vim', {'for': 'tex'}

" Swift 
Plug 'bumaociyuan/vim-swift'  " syntax (fork from official)

" coc-json, coc-html
" coc-python

" Haskell
" https://github.com/neovimhaskell/haskell-vim
" https://github.com/chrisdone/hindent
" https://github.com/jaspervdj/stylish-haskell

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

" Auxiliary indentation indicator
Plug 'Yggdroot/indentLine'

" Snippets
Plug 'SirVer/ultisnips'
":CocInstall coc-snippets
" Plug 'honza/vim-snippets'

" ------ Initialze Plugin System ------
call plug#end()

" Load config files
for f in glob($VIMRCDIR.'/plugconf/*.vim', 0, 1)
  if f !~? 'test_'
    exec 'so' f
  endif
endfor

" GUI settings
set termguicolors  " need +termguicolors
if has('gui_running')
  colorscheme github
else
  colorscheme gruvbox
  let g:airline_theme = 'gruvbox'
  " let g:gruvbox_contrast_dark = 'hard'
  " TODO: overwrite airline, remove charging status
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

" start a clientserver under terminal?
" if empty(v:servername) && exists('*remote_startserver')
" call remote_startserver('VIM')
" endif


"--------------------------------------------------------------
" Custom Functions
"--------------------------------------------------------------
for f in glob($VIMRCDIR.'/functions/*.vim', 0, 1)
  exec 'so' f
endfor

" File Header
au BufNewFile *.cpp,*.[ch],*.sh,*.rb,*.java,*.py,*.ts exec ":call SetHeader()"

" Functional Keys
nmap <F2> :TagbarToggle<cr>
nmap <F3> :NERDTreeToggle<cr>
nmap <F4> :OpenREPL<cr>
nmap <F5> :CompileRun<cr>
nmap <F6> :ALEFix<cr>

" TODO: more ctags into a fn
nnoremap <leader>t command! MakeTags !ctags -R .<cr>

" TODO: enable wordprocessingmode for certain filetypes
" :autocmd FileType javascript nnoremap <buffer> <localleader>c I//<esc>

" Colour Column
" TODO: exclude latex
" The line length should be limited to 72 characters, 79 at max.
" see https://www.python.org/dev/peps/pep-0008/#maximum-line-length.
" highlight OverLength ctermbg=red ctermfg=white guibg=#592929
" match OverLength /\%280v.\+/
" set colorcolumn=+1  " fancier?
