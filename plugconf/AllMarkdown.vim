" Vim's maintained runtime now supplies Markdown syntax, header motions, and
" folding.  Keep configuration on the native surface and reserve plugins for
" preview and table-of-contents generation.
let g:markdown_folding = 1
let g:markdown_recommended_style = 0
let g:markdown_syntax_conceal = 0
" Updating a generated TOC is explicit, just like formatting with F6.
let g:vmt_auto_update_on_save = get(g:, 'vmt_auto_update_on_save', 0)

" WebPreview owns Markdown rendering, browser configuration and sessions.
call webpreview#setup()
