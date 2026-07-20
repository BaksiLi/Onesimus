" Vim's maintained runtime now supplies Markdown syntax, header motions, and
" folding.  Keep configuration on the native surface and reserve plugins for
" preview and table-of-contents generation.
let g:markdown_folding = 1
let g:markdown_recommended_style = 0
let g:markdown_syntax_conceal = 0

" Let markdown-preview choose the platform browser unless the user overrides
" it before sourcing Onesimus.
let g:mkdp_browser = get(g:, 'mkdp_browser', '')
let g:mkdp_page_title = '${name}_preview'
