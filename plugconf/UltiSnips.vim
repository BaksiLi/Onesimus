let g:UltiSnipsExpandTrigger='<C-e>'

" An absolute snippets directory must stand alone in UltiSnips.  Standard LSP
" completion is handled by ALE; this directory remains the personal layer.
let g:UltiSnipsSnippetDirectories=[$VIMRCDIR.'/snippets']

" The checkout is on 'runtimepath' for autoload/, which also exposes
" snippets/ to UltiSnips' SnipMate reader.  These files are UltiSnips syntax.
let g:UltiSnipsEnableSnipMate = 0
