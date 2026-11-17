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
" autoload/ holds code that loads on first use.  The root has no plugin/ or
" ftplugin/ directory, so joining 'runtimepath' runs nothing at startup;
" snippets/ is kept from UltiSnips' SnipMate reader in plugconf/UltiSnips.vim.
if index(split(&runtimepath, ','), $VIMRCDIR) < 0
  execute 'set runtimepath^='.fnameescape($VIMRCDIR)
endif

if v:version < 802 || !has('job') || !has('channel') || !has('timers')
      \ || !exists('*sha256')
  echoerr 'Onesimus requires Vim 8.2+ with +job, +channel, +timers, and sha256().'
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

" Personal options must be available before plugin declarations are evaluated.
if filereadable($VIMRCDIR.'/custom/settings.vim')
  execute 'source '.fnameescape($VIMRCDIR.'/custom/settings.vim')
endif

" g:asc_uname
" TODO: dependencies for lua, python

"--------------------------------------------------------------
" General Configurations and Keymaps
"--------------------------------------------------------------
" Set alternative leader key (default: '\')
let mapleader = '\'
let maplocalleader = ','

" Previews open through OnesimusOpenBrowser, which tests replace.
let g:webpreview_browserfunc = 'OnesimusOpenBrowser'
let g:webpreview_notify = 'OnesimusNotify'
let g:webpreview_open = extend({'tex': 'OnesimusTexView'}, get(g:, 'webpreview_open', {}))
let g:webpreview_tex_port = get(g:, 'webpreview_tex_port', get(g:, 'onesimus_tex_browser_port', 0))

" ------ Meta ------
" One command, :One, carries every Onesimus action (autoload/one.vim); its
" keys are mapped after the modules have registered their actions.
command! -nargs=* -complete=customlist,one#complete One call one#run(<q-args>)

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

" Source writes are always explicit.  Swap/undo/backups provide recovery
" without turning idle timers, compilation, or focus changes into writes.
set noautowrite noautowriteall
set autoread
set confirm       " ask before abandoning a modified buffer
set writebackup

let s:onesimus_state_base = empty($XDG_STATE_HOME)
      \ ? expand('~/.local/state') : expand($XDG_STATE_HOME)
let s:onesimus_recovery = s:onesimus_state_base.'/onesimus/vim'
if isdirectory(s:onesimus_recovery)
      \ || mkdir(s:onesimus_recovery, 'p', 0700)
  for s:recovery_kind in ['backup', 'swap', 'undo']
    call mkdir(s:onesimus_recovery.'/'.s:recovery_kind, 'p', 0700)
  endfor
  let &backupdir = s:onesimus_recovery.'/backup//'
  let &directory = '.,'.s:onesimus_recovery.'/swap//,/var/tmp//,/tmp//'
  let &undodir = s:onesimus_recovery.'/undo//'
  set backup undofile
endif
unlet! s:recovery_kind

set cmdheight=1
set sidescroll=10
" Shorter updatetime for CursorHold & CursorHoldI
set updatetime=300
set timeoutlen=750

" Manual folding
set foldmethod=manual
set nofoldenable
set foldopen+=jump,insert
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
nnoremap <C-H> <C-W><C-H>
" Keep Ctrl-L's familiar redraw meaning for unreliable remote terminals.
" Moving to the right split remains available as Vim's native Ctrl-W l.
nnoremap <silent> <C-L> :<C-U>One redraw<CR>

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
execute 'source '.fnameescape($VIMRCDIR.'/config/plugins.vim')

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
" Gruvbox and Nord live in packages/themes; the status and tab lines are
" Onesimus's own (functions/Statusline.vim).
if get(g:, 'onesimus_extra_themes', 0)
  Plug 'junegunn/seoul256.vim'
  Plug 'sickill/vim-monokai'
endif

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
" Markdown preview is bundled with WebPreview.vim; external providers are optional.
call OnesimusPlugin('BaksiLi/mdtoc.vim', { 'for': 'markdown' })

" TeX
" requires latexmk, for example: `sudo tlmgr install latexmk`
" VimTeX already loads through ftplugins/autoload.  External lazy loading can
" break inverse search; v2.15 preserves Onesimus's unqualified Vim 8.2 floor.
Plug 'lervag/vimtex', { 'tag': 'v2.15' }

" VimScript Reference
if get(g:, 'onesimus_developer_plugins', 0)
  Plug 'tweekmonster/helpful.vim', { 'on': 'HelpfulVersion' }
  Plug 'junegunn/vader.vim', { 'on': 'Vader' }
endif

" Highlight not already covered by Vim's current runtime.
Plug 'BaksiLi/vim-applescript'
" Plug 'leafgarland/typescript-vim'
" Plug 'rust-lang/rust.vim'
" Plug 'jparise/vim-graphql'

" Web
Plug 'mattn/emmet-vim', { 'for': 'html' }

" Haskell
" Portable syntax and indentation for Haskell source and Cabal manifests.
Plug 'neovimhaskell/haskell-vim', { 'for': ['haskell', 'cabal'] }



" ------ Editing ------
" Parentheses helper
Plug 'tpope/vim-surround'
" Repeat plugin actions with .
Plug 'tpope/vim-repeat'
" Comment operator (gc)
Plug 'tpope/vim-commentary'
" Tabular
Plug 'godlygeek/tabular', { 'on': 'Tabularize' }

" Chinese word motions and text objects.  Keep the plugin out of Vim builds
" without +python3, and pin its native backend to a reproducible release.
" has('python3') loads libpython in dynamic builds (about 5 ms in MacVim), so
" startup asks only whether the feature was compiled in; the real check waits
" until a buffer contains Han text.
if has('python3_dynamic') || has('python3')
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
" Lock the distribution before personal declarations, which may override it.
call OnesimusLockPlugins()
if filereadable($VIMRCDIR.'/custom/plugins.vim')
  execute 'source '.fnameescape($VIMRCDIR.'/custom/plugins.vim')
endif

" ------ Initialize Plugin System ------
call plug#end()
for s:package in ['webpreview.vim', 'themes', 'autocorrect']
  let s:package = $VIMRCDIR.'/packages/'.s:package
  if index(split(&runtimepath, ','), s:package) < 0
    execute 'set runtimepath^='.fnameescape(s:package)
  endif
endfor
unlet s:package
runtime plugin/webpreview.vim

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

" The provider hook also covers an explicit :EditorConfigReload.  Register
" once across :One reload; the named function picks up later definitions.
if exists(':EditorConfigReload') && !get(g:, 'onesimus_prose_editorconfig_hook', 0)
  call editorconfig#AddNewHook(function('OnesimusEnforceProseSoftWrap'))
  let g:onesimus_prose_editorconfig_hook = 1
endif

" AsyncRun for fugitive
if PlugInstalled('asyncrun.vim')
  command! -bang -nargs=* -complete=file Make AsyncRun -program=make @ <args>
endif

" GUI settings
if exists('+termguicolors')
  set termguicolors
endif

" Zellij versions before 0.44.1 could leave the active background colour in
" end-of-line padding when Vim scrolled one screen row.  A long-lived remote
" session may still be served by that older process after the client binary is
" upgraded.  Stop advertising background-colour erase inside Zellij; Vim then
" repaints those cells explicitly.  The small bandwidth cost is preferable to
" stale coloured stripes on a touch terminal.
if !exists('s:onesimus_zellij_t_ut_saved')
  let s:onesimus_zellij_t_ut_saved = ''
  let s:onesimus_zellij_t_ut_changed = 0
endif
function! OnesimusConfigureTerminalRendering() abort
  if !exists('+t_ut')
    return
  endif
  if !empty($ZELLIJ) && get(g:, 'onesimus_zellij_bce_workaround', 1)
    if !s:onesimus_zellij_t_ut_changed
      let s:onesimus_zellij_t_ut_saved = &t_ut
    endif
    set t_ut=
    let s:onesimus_zellij_t_ut_changed = 1
  elseif s:onesimus_zellij_t_ut_changed
    let &t_ut = s:onesimus_zellij_t_ut_saved
    let s:onesimus_zellij_t_ut_changed = 0
  endif
endfunction
call OnesimusConfigureTerminalRendering()

function! OnesimusRedraw() abort
  redraw!
  echohl MoreMsg
  echomsg 'Onesimus: terminal display redrawn.'
  echohl None
  return 1
endfunction
call one#define('redraw', '*', function('OnesimusRedraw'))
if has('gui_running')
  set guioptions-=T
  set guitablabel=%M%t
  colorscheme nord
else
  set background=dark
  colorscheme gruvbox
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
" VimTeX inverse search needs a server even in terminal Vim.  A per-process
" name avoids collisions across tmux/zellij panes and simultaneous SSH jobs.
if has('clientserver') && empty(v:servername) && exists('*remote_startserver')
      \ && has('ttyin') && has('ttyout')
      \ && (!empty($DISPLAY) || has('socketserver'))
  let s:onesimus_server_error = v:errmsg
  try
    call remote_startserver('ONESIMUS_'.getpid())
  catch
    " Some headless builds advertise clientserver without a usable transport.
  finally
    let v:errmsg = s:onesimus_server_error
    unlet s:onesimus_server_error
  endtry
endif


"--------------------------------------------------------------
" Custom Functions
"--------------------------------------------------------------
" Load all functions
SourceAll $VIMRCDIR.'/functions'

" \ (global), \\ (this file) and F2-F6, from the tables in autoload/one.vim.
call one#map()

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
