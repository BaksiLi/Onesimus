" Real built-in Markdown transport and unsaved-draft behavior for live providers.
let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
let g:onesimus_preview_host = 'preview.example'
let $SSH_CONNECTION = 'writing preview test'
execute 'source '.fnameescape($VIMRCDIR.'/init.vim')
let s:root = tempname()
call mkdir(s:root, 'p')
let s:opened = []
function! TestWritingBrowser(url) abort
  call add(s:opened, a:url)
  return 1
endfunction
let g:webpreview_browserfunc = 'TestWritingBrowser'
function! s:Wait(condition) abort
  for l:attempt in range(250)
    if eval(a:condition) | return 1 | endif
    sleep 20m
  endfor
  return 0
endfunction
function! s:Run() abort
  try
    call assert_false(has_key(g:plugs, 'markdown-preview.nvim'), 'preview is built in')
    call writefile(['Saved Markdown.'], s:root.'/draft.md')
    execute 'edit '.fnameescape(s:root.'/draft.md')
    call setline(1, 'Unsaved Markdown.')
    call feedkeys("\<F5>", 'xt')
    call assert_true(s:Wait('!empty(webpreview#markdown#url())'), 'F5 starts the bundled Markdown provider')
    let l:url = webpreview#markdown#url()
    call assert_match('http://preview\.example:', execute('messages'))
    call assert_equal(webpreview#url(l:url), s:opened[-1])
    let l:fetch = 'import urllib.request,json,sys;d=json.load(urllib.request.urlopen(sys.argv[1]+"state"));print(d["text"])'
    let l:text = system('python3 -c '.shellescape(l:fetch).' '.shellescape(l:url))
    call assert_match('Unsaved Markdown.', l:text)
    call assert_true(&modified)
    call assert_equal(['Saved Markdown.'], readfile(s:root.'/draft.md'))
    call feedkeys("\<F5>", 'xt')
    call assert_equal(l:url, webpreview#markdown#url(), 'reopening reuses its session')
    execute 'source '.fnameescape($VIMRCDIR.'/functions/Writing.vim')
    runtime plugin/webpreview.vim
    call assert_equal(l:url, webpreview#markdown#url(), 'reload preserves the reader')
    if exists(':CogPreview') == 2
      call setline(1, ['```cog', '- [C] An unsaved inquiry.', '```'])
      let g:cogitatum_preview_open = 0
      WebPreviewInquiry
      call assert_true(s:Wait('!empty(cogitatum#preview#Url(bufnr("")))'))
    endif
    OnesimusWritingPreviewStop
    call assert_equal('', webpreview#markdown#url())
    if exists(':CogPreview') == 2
      call assert_equal('', cogitatum#preview#Url(bufnr('')))
      call writefile(['- [C] Saved claim.'], s:root.'/draft.cog.md')
      execute 'edit '.fnameescape(s:root.'/draft.cog.md')
      call setline(1, '- [C] Unsaved claim.')
      call feedkeys("\<F5>", 'xt')
      call assert_true(s:Wait('!empty(cogitatum#preview#Url(bufnr("")))'))
      call assert_true(&modified)
      call assert_equal(['- [C] Saved claim.'], readfile(s:root.'/draft.cog.md'))
      OnesimusWritingPreviewStop
    endif
  catch
    call add(v:errors, v:exception.' at '.v:throwpoint)
  finally
    call webpreview#markdown#stop()
    if exists(':CogPreviewStop') == 2
      CogPreviewStop
    endif
    for l:id in popup_list() | call popup_close(l:id) | endfor
    enew!
    call delete(s:root, 'rf')
  endtry
  call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors, '/tmp/onesimus-writing-preview-result')
  if !empty(v:errors) | cquit | endif
  qall!
endfunction
autocmd VimEnter * ++nested call <SID>Run()
