" Cogitatum inquiry notes.  The vim-cogitatum plugin supplies filetype
" detection, syntax (including Markdown fences), previews and ALE's `cog`
" language server; declare it in custom/plugins.vim (see the example there).
" Onesimus selects the linter, since ALE runs only explicit linters here.
" WebPreview.vim configures the preview hostname, opener and text selection.
if empty(globpath(&runtimepath, 'ale_linters/cogitatum/cog.vim'))
  finish
endif

let g:ale_linters = get(g:, 'ale_linters', {})
let g:ale_linters.cogitatum = ['cog']
" Markdown notes may carry ```cog fences; notes without them get no diagnostics.
if index(get(g:ale_linters, 'markdown', []), 'cog') < 0
  let g:ale_linters.markdown = get(g:ale_linters, 'markdown', []) + ['cog']
endif

