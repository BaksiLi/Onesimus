" ------ vimtex ------
" TODO: add configurable components
" let g:vimtex_compiler_progname = 'nvr'
let g:tex_flavor='latex'
" Onesimus owns browser previews; VimTeX owns compilation and SyncTeX data.
let g:vimtex_view_enabled=0
let g:vimtex_view_automatic=0
let g:vimtex_quickfix_mode=0
" Onesimus owns formula presentation; avoid a second, partial conceal layer.
let g:vimtex_syntax_conceal_disable = 1
