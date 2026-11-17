" Standalone plugin checks: no Onesimus runtime or writing functions loaded.
set nocompatible
let s:package = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^='.fnameescape(s:package)
let g:webpreview_host = 'preview.example'
runtime plugin/webpreview.vim

let g:opened = []
let g:stopped = []
command! CogPreview call add(g:opened, 'cogitatum')
command! CogPreviewStop call add(g:stopped, 'cogitatum')
function! TestOpenBrowser(url) abort
  call add(g:opened, a:url)
  return 1
endfunction
function! TestTeXPolicy() abort
  call add(g:opened, 'tex host policy')
  return 1
endfunction
function! TestMarkdownPolicy() abort
  call add(g:opened, 'markdown')
  return 1
endfunction
let g:webpreview_browserfunc = 'TestOpenBrowser'
let g:webpreview_open = {'tex': 'TestTeXPolicy', 'markdown': 'TestMarkdownPolicy'}

call assert_false(exists('*OnesimusWritingPreview'))
call assert_equal(2, exists(':WebPreview'))
call assert_equal(2, exists(':WebPreviewChanges'))
call assert_equal(0, exists(':MarkdownPreview'), 'no external preview command is required')
call assert_equal('webpreview#show', g:cogitatum_preview_browserfunc)
call assert_equal('webpreview#select', g:cogitatum_preview_selectfunc)
call assert_equal('preview.example', g:cogitatum_preview_host)
call assert_equal('http://preview.example:12345/token/', webpreview#url('http://127.0.0.1:12345/token/'))
call assert_equal('https://other.example/path', webpreview#url('https://other.example/path'))

enew
setlocal filetype=markdown
call setline(1, 'Unsaved Markdown with inquiry fences.')
let s:tick = b:changedtick
WebPreview
WebPreviewInquiry
WebPreviewStop
call assert_equal(['markdown', 'cogitatum'], g:opened)
call assert_equal(['cogitatum'], g:stopped)
call assert_equal(s:tick, b:changedtick)
call assert_true(&modified)
setlocal filetype=cogitatum
WebPreview
call assert_equal('cogitatum', g:opened[-1])
setlocal filetype=tex
WebPreview
call assert_equal('tex host policy', g:opened[-1])
call webpreview#show('http://localhost:321/token/')
call assert_equal('http://preview.example:321/token/', g:opened[-1])

let g:cogitatum_preview_browserfunc = 'UserCogBrowser'
call webpreview#setup()
call assert_equal('UserCogBrowser', g:cogitatum_preview_browserfunc)

let $SSH_CONNECTION = 'mobile test'
call assert_true(webpreview#headless())
let s:maps = maparg('<F5>', 'n')
runtime plugin/webpreview.vim
call assert_equal(s:maps, maparg('<F5>', 'n'), 'plugin installs no mappings')

setlocal filetype=markdown
call setline(1, '😀 前文 [漢字]^^(かんじ) 後文。')
call assert_true(webpreview#select('[漢字]^^(かんじ)', 1))
normal! y
call assert_equal('[漢字]^^(かんじ)', getreg('"'), 'annotation source survives Unicode before its byte columns')
call assert_true(&modified, 'source selection preserves the unsaved draft')

let s:help = tempname()
call mkdir(s:help.'/doc', 'p')
call writefile(readfile(s:package.'/doc/webpreview.txt'), s:help.'/doc/webpreview.txt')
execute 'helptags '.fnameescape(s:help.'/doc')
execute 'set runtimepath^='.fnameescape(s:help)
help webpreview-options
call assert_equal('help', &filetype)
call assert_match('OPTIONS', getline('.'))
call delete(s:help, 'rf')

if !empty(v:errors)
  for s:error in v:errors | echomsg s:error | endfor
  cquit
endif
qall!
