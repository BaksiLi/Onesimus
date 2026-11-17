" Cogitatum inquiry notes.  The vim-cogitatum plugin supplies filetype
" detection, syntax (including Markdown fences), previews and ALE's `cog`
" language server; declare it in custom/plugins.vim (see the example there).
" Onesimus selects the linter, since ALE runs only explicit linters here.
" WebPreview.vim configures the preview hostname, opener and text selection.
" The terminal views and the browser inquiry are :One verbs whenever their
" plugins are loaded, even when the linter below is missing.
function! s:HasCommand(name) abort
  return exists(':'.a:name) == 2
endfunction
function! s:CogFences() abort
  return search('^\s*```\s*cog\>', 'nw') > 0
endfunction
call one#define('read', ['cogitatum', 'markdown'], 'CogRead',
      \ {-> s:HasCommand('CogRead') && (&l:filetype ==# 'cogitatum' || s:CogFences())})
call one#define('map', ['cogitatum', 'markdown'], 'CogMap',
      \ {-> s:HasCommand('CogMap') && (&l:filetype ==# 'cogitatum' || s:CogFences())})
call one#define('inquiry', ['cogitatum', 'markdown'], 'WebPreviewInquiry',
      \ {-> s:HasCommand('WebPreviewInquiry') && (&l:filetype ==# 'cogitatum' || s:CogFences())})

if empty(globpath(&runtimepath, 'ale_linters/cogitatum/cog.vim'))
  finish
endif

let g:ale_linters = get(g:, 'ale_linters', {})
let g:ale_linters.cogitatum = ['cog']
" Markdown notes may carry ```cog fences; notes without them get no diagnostics.
if index(get(g:ale_linters, 'markdown', []), 'cog') < 0
  let g:ale_linters.markdown = get(g:ale_linters, 'markdown', []) + ['cog']
endif

