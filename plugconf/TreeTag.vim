" ------ NERDTree ------
let g:NERDTreeWinPos = 'left'
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif
let g:NERDTreeQuitOnOpen=1

let g:NERDTreeFileExtensionHighlightFullName = 1
let g:NERDTreeExactMatchHighlightFullName = 1
let g:NERDTreePatternMatchHighlightFullName = 1
let g:NERDTreeHighlightFolders = 1         
let g:NERDTreeHighlightFoldersFullName = 1 
let g:NERDTreeDirArrowExpandable='▷'
let g:NERDTreeDirArrowCollapsible='▼'

" let g:NERDTreeShowHidden=1
" let NERDTreeIgnore=['\.pyc$', '\~$'] "ignore files in NERDTree, maybe read
" .gitignore?

" Open a NERDTree automatically when vim starts up if no files were specified
" autocmd StdinReadPre * let s:std_in=1
" autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif

" ------ tagbar ------
let g:tagbar_right = 1
let g:tagbar_width = 30
let g:tagbar_iconchars = ['▶', '▼']

" For UltiSnips
" https://github.com/majutsushi/tagbar/wiki#ultisnips
let g:tagbar_type_snippets = {
    \ 'ctagstype' : 'snippets',
    \ 'kinds' : [
        \ 's:snippets',
    \ ]
\ }
