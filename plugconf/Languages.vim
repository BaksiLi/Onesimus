" ------ vimtex ------
" TODO: add configurable components
" let g:vimtex_compiler_progname = 'nvr'
let g:tex_flavor='latex'
if !exists('g:vimtex_view_method') && get(g:, 'asc_uname', '') ==# 'darwin'
  let g:vimtex_view_method='skim'
endif
let g:vimtex_quickfix_mode=0
" set conceallevel=1
" need set concealcursor-=n
" Vimtex's maintained syntax layer now owns TeX concealment; no second
" tex-conceal plugin is layered over it.
