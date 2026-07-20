" Native action guide and concise popup integration test.
" Run with:
"   vim -Nu tests/guide.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

function! s:PopupText(id) abort
  return join(getbufline(winbufnr(a:id), 1, '$'), "\n")
endfunction

function! s:GuideScriptID() abort
  for l:line in split(execute('scriptnames'), "\n")
    if l:line =~# 'functions/Guide\.vim$'
      return str2nr(matchstr(l:line, '^\s*\zs\d\+'))
    endif
  endfor
  return -1
endfunction

function! s:RunGuideTests() abort
  " Git-aware actions are contextual.  Give the test its own repository marker
  " instead of relying on how the outer checkout was produced; actions/checkout
  " can legitimately use an archive when Git is not yet present in a container.
  let l:original_cwd = getcwd()
  let l:git_fixture = tempname()
  call mkdir(l:git_fixture.'/.git', 'p')
  execute 'lcd '.fnameescape(l:git_fixture)

  call assert_true(OnesimusPopupSupported())
  call assert_false(has_key(g:plugs, 'vim-which-key'),
        \ 'the action guide is native Vim rather than another UI dependency')
  call assert_match('OnesimusGuide', maparg('\', 'n'))
  call assert_match('OnesimusGuide', maparg('<leader>.', 'n'))
  call assert_match('OnesimusHealth', maparg('<leader>li', 'n'))
  call assert_match('OnesimusIndentToggle', maparg('<leader>ti', 'n'))
  call assert_match('OnesimusParenthesisToggle', maparg('<leader>tp', 'n'))
  call assert_match('WPModeToggle', maparg('<leader>tw', 'n'))
  call assert_match('ToggleBackground', maparg('<leader>tb', 'n'))

  let l:id = OnesimusGuide('global')
  let l:root = s:PopupText(l:id)
  call assert_match('ACTIONS', l:root)
  call assert_match('Find', l:root)
  call assert_notmatch('Current buffer', l:root,
        \ 'empty buffers do not advertise irrelevant code actions')
  call assert_match('Git', l:root)
  call assert_match('View', l:root)
  call assert_match('Onesimus', l:root)
  call assert_notmatch('Resize', l:root)
  call assert_notmatch('Command History', l:root)
  call assert_notmatch('Push', l:root)

  call OnesimusGuideFilter(l:id, 'f')
  let l:find = s:PopupText(l:id)
  call assert_match('Files', l:find)
  call assert_match('Buffers', l:find)
  call assert_match('Search project', l:find)
  call assert_match('Recent files', l:find)
  call OnesimusGuideFilter(l:id, "\<BS>")
  call assert_match('ACTIONS', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, "\<Esc>")

  let l:id = OnesimusGuide('global')
  call OnesimusGuideFilter(l:id, 'o')
  let l:system = s:PopupText(l:id)
  call assert_match('Update', l:system)
  call assert_match('Usage', l:system)
  let v:errmsg = ''
  call OnesimusGuideFilter(l:id, 'r')
  call feedkeys('', 'x')
  call assert_notmatch('E127:', v:errmsg,
        \ 'choosing reload runs after the guide filter has returned')

  enew
  file /tmp/onesimus-guide.py
  setlocal filetype=python
  let l:id = OnesimusGuide('context')
  let l:code = s:PopupText(l:id)
  call assert_match('Run / compile', l:code)
  call assert_match('Format buffer', l:code)
  call assert_match('Problems', l:code)
  call assert_match('Buffer symbols', l:code)
  call assert_notmatch('Focus writing', l:code)
  call OnesimusGuideFilter(l:id, "\<Esc>")

  doautocmd User ALELSPStarted
  call assert_equal('', maparg('gi', 'n'),
        \ 'LSP integration preserves Vim''s last-insert command')
  call assert_equal('', maparg('gt', 'n'),
        \ 'LSP integration preserves Vim''s next-tab command')
  let l:id = OnesimusGuide('context')
  let l:lsp = s:PopupText(l:id)
  call assert_match('Navigate symbol', l:lsp)
  call assert_match('Rename symbol', l:lsp)
  call assert_match('Code action', l:lsp)
  call OnesimusGuideFilter(l:id, 'g')
  let l:navigation = s:PopupText(l:id)
  call assert_match('GO TO', l:navigation)
  call assert_match('Definition', l:navigation)
  call assert_match('References', l:navigation)
  call assert_match('Implementation', l:navigation)
  call assert_match('Type definition', l:navigation)
  call OnesimusGuideFilter(l:id, "\<Esc>")

  let b:onesimus_lsp_ready = 0
  let v:errmsg = ''
  call assert_false(OnesimusLSPNavigate('implementation'))
  call assert_equal('', v:errmsg,
        \ 'navigation without a server is a friendly no-op')
  let b:onesimus_lsp_ready = 1
  silent! delcommand ALEGoToImplementation
  silent! delcommand ALEGoToTypeDefinition
  command! ALEGoToImplementation let g:onesimus_test_navigation = 'implementation'
  command! ALEGoToTypeDefinition let g:onesimus_test_navigation = 'type_definition'
  call assert_true(OnesimusLSPNavigate('implementation'))
  call assert_equal('implementation', g:onesimus_test_navigation)
  call assert_true(OnesimusLSPNavigate('type_definition'))
  call assert_equal('type_definition', g:onesimus_test_navigation)

  enew
  call setline(1, 'An ASCII Markdown buffer.')
  setfiletype markdown
  let l:id = OnesimusGuide('context')
  let l:prose = s:PopupText(l:id)
  call assert_match('Preview', l:prose)
  call assert_match('Focus writing', l:prose)
  call OnesimusGuideFilter(l:id, "\<Esc>")

  setlocal filetype=python
  OnesimusHealth
  let l:popups = popup_list()
  call assert_false(empty(l:popups))
  let l:health = s:PopupText(l:popups[-1])
  call assert_match('TOOL STATUS', l:health)
  call assert_match('Filetype  python', l:health)
  call assert_match('Details.*:ALEInfo', l:health)
  call OnesimusPopupFilter(l:popups[-1], 'q')

  let l:saved_jieba_error = get(g:, 'onesimus_jieba_error', '')
  let g:onesimus_jieba_error = 'synthetic backend failure'
  OnesimusHealth
  let l:health_popup = popup_list()[-1]
  call assert_match('failed.*words.*synthetic backend failure',
        \ s:PopupText(l:health_popup))
  call popup_close(l:health_popup)
  let g:onesimus_jieba_error = l:saved_jieba_error

  let l:detail_popup = OnesimusPopup('FILTER TEST', ['details'])
  call assert_equal(0, OnesimusPopupFilter(l:detail_popup, 'z'),
        \ 'an asynchronous detail popup passes unknown keys to Vim')
  call popup_close(l:detail_popup)
  let l:notice = OnesimusNotify('NOTICE TEST', ['completed'], 0)
  call assert_true(l:notice > 0)
  call assert_false(has_key(popup_getoptions(l:notice), 'filter'),
        \ 'notifications never install a key filter')
  call popup_close(l:notice)

  " Exercise the old-Vim renderer even though this test Vim has popup support.
  let l:sid = s:GuideScriptID()
  call assert_true(l:sid > 0)
  call feedkeys("\<Esc>", 't')
  execute 'call <SNR>'.l:sid.'_FallbackGuide('
        \ .'<SNR>'.l:sid.'_GlobalMenu())'
  call assert_equal('', v:errmsg)

  execute 'lcd '.fnameescape(l:original_cwd)
  call delete(l:git_fixture, 'rf')

  call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors,
        \ '/tmp/onesimus-guide-result')
  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_guide_test
  autocmd!
  autocmd VimEnter * call <SID>RunGuideTests()
augroup END
