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

  let l:id = OnesimusGuide()
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

  call OnesimusGuideFilter(l:id, 't')
  let l:view = s:PopupText(l:id)
  call assert_match('Redraw terminal display.*Ctrl-L', l:view)
  call OnesimusGuideFilter(l:id, "\<BS>")
  call assert_match('ACTIONS', s:PopupText(l:id))

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

  enew
  file /tmp/onesimus-guide.hs
  setlocal filetype=haskell
  let l:id = OnesimusGuide('context')
  let l:haskell = s:PopupText(l:id)
  call assert_match('Check code', l:haskell)
  call assert_notmatch('Run / compile', l:haskell)
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
  call assert_match('^No unsaved edits', OnesimusTexMenuSummary(),
        \ 'an untouched unnamed buffer must not claim it has been saved')
  file /tmp/onesimus-guide.tex
  call setline(1, 'A modified TeX buffer.')
  setlocal filetype=tex
  call feedkeys("\\\\", 'xt')
  call assert_match('TEX PAPER', s:PopupText(popup_list()[-1]),
        \ 'typing two backslashes follows the actual mapping into file actions')
  call popup_close(popup_list()[-1])
  let l:id = OnesimusGuide()
  call assert_match('ACTIONS', s:PopupText(l:id),
        \ 'the default entry stays global when the filetype changes')
  call assert_match('\\.*Current file · TeX paper', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, '\')
  let l:tex = s:PopupText(l:id)
  call assert_match('TEX PAPER', l:tex)
  call assert_match('Unsaved', l:tex)
  call assert_match('Save, build & preview (F5)', l:tex)
  call assert_match('Outline / sections', l:tex)
  call assert_match('Enter focus mode', l:tex)
  call assert_match('Sentence lines (review)', l:tex)
  call assert_match('Use raw formulas', l:tex)
  call assert_match('Save text only', l:tex)
  call assert_match('Compilation errors', l:tex)
  call assert_match('Browser preview', l:tex)
  call assert_match('Preview changes (latexdiff)', l:tex)
  call assert_match('More tools', l:tex)
  call assert_notmatch('Write & revise\|Build & problems\|File & collaboration', l:tex,
        \ 'daily actions have no category layer')
  call assert_notmatch('Compiler log\|Check disk updates\|math symbols', l:tex)
  call assert_equal(11, len(getbufline(winbufnr(l:id), 1, '$')) - 5,
        \ 'file actions have one Back row and no second global-menu branch')
  call assert_match('↑↓ select.*Enter/tap', l:tex)
  call assert_equal('a', &mouse)
  call assert_equal('button', popup_getoptions(l:id).close)
  call OnesimusGuideFilter(l:id, "\<Down>")
  call assert_match('^> v', getbufline(winbufnr(l:id), 5)[0])
  call OnesimusGuideFilter(l:id, 'o')
  call assert_match('TEX TOOLS', s:PopupText(l:id))
  call assert_match('Compiler log', s:PopupText(l:id))
  call assert_match('Inspect final PDF externally', s:PopupText(l:id))
  call assert_match('Check disk updates', s:PopupText(l:id))
  call assert_match('TeX style warnings', s:PopupText(l:id))
  call assert_match('Stop browser preview', s:PopupText(l:id))
  call assert_notmatch('math symbols\|Check installed tools', s:PopupText(l:id))
  call assert_match('<.*Back', getbufline(winbufnr(l:id), 3)[0])
  if exists('*test_setmouse')
    redraw
    let l:pos = popup_getpos(l:id)
    call test_setmouse(l:pos.core_line + 3 - l:pos.firstline, l:pos.core_col + 2)
    call OnesimusGuideFilter(l:id, "\<LeftMouse>")
    call assert_match('TEX TOOLS', s:PopupText(l:id), 'touch press alone never activates Back')
    call OnesimusGuideFilter(l:id, "\<LeftRelease>")
    call assert_match('TEX PAPER', s:PopupText(l:id), 'release activates Back')
  else
    call OnesimusGuideFilter(l:id, "\<BS>")
  endif
  call assert_match('\n> o', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, "\<Left>")
  call assert_match('ACTIONS', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, "\<Esc>")
  call assert_equal('', &mouse,
        \ 'closing the guide returns selection ownership to the terminal')

  let l:saved_lines = &lines
  let l:saved_columns = &columns
  try
    let &lines = 12
    let &columns = 40
    let l:id = OnesimusGuide('context')
    for l:step in range(1, 10)
      call OnesimusGuideFilter(l:id, "\<ScrollWheelDown>")
    endfor
    redraw
    call assert_true(get(popup_getpos(l:id), 'firstline', 1) > 1,
          \ 'touch/wheel selection remains visible on a short terminal')
    let l:position = popup_getpos(l:id)
    call assert_true(l:position.width <= &columns)
    let l:selected_line = match(getbufline(winbufnr(l:id), 1, '$'), '^> o') + 1
    call assert_true(l:selected_line > 0
          \ && l:position.firstline <= l:selected_line
          \ && l:position.firstline + l:position.core_height > l:selected_line,
          \ 'the selected More tools row is visible before Enter can run it: '
          \ .string(l:position))
    call assert_false(popup_getoptions(l:id).wrap,
          \ 'short menu labels do not become multi-row touch targets')
    call OnesimusGuideFilter(l:id, "\<Esc>")
  finally
    let &lines = l:saved_lines
    let &columns = l:saved_columns
  endtry

  " Sentence layout is an explicit first-level action.
  let g:onesimus_guide_alias_ran = 0
  command! OnesimusTexSentenceLines let g:onesimus_guide_alias_ran = 1
  let l:tick = b:changedtick
  let l:id = OnesimusGuide('context')
  call OnesimusGuideFilter(l:id, 'n')
  call feedkeys('', 'x')
  call assert_equal(1, g:onesimus_guide_alias_ran)
  call assert_equal(l:tick, b:changedtick,
        \ 'menu navigation never edits the source')

  enew
  call setline(1, 'An ASCII Markdown buffer.')
  setfiletype markdown
  let l:id = OnesimusGuide('context')
  let l:prose = s:PopupText(l:id)
  call assert_match('MARKDOWN WRITING', l:prose)
  call assert_match('Browser preview (F5)', l:prose)
  call assert_notmatch('Save & preview\|Inquiry fences', l:prose)
  call assert_match('Enter focus mode', l:prose)
  call assert_match('Word count', l:prose)
  call assert_match('Use raw formulas', l:prose)
  call assert_match('Spelling', l:prose)
  call assert_match('More tools', l:prose)
  call assert_notmatch('File & collaboration\|Format text\|Writing help', l:prose)
  call assert_notmatch('Buffer symbols\|Run / compile', l:prose)
  call OnesimusGuideFilter(l:id, 'o')
  call assert_match('WRITING TOOLS', s:PopupText(l:id))
  call assert_match('Check disk updates', s:PopupText(l:id))
  call assert_match('Stop browser preview', s:PopupText(l:id))
  call assert_match('Format text (F6)', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, "\<Esc>")

  if exists(':CogPreview') == 2
    call setline(1, ['```cog', '- [C] A claim.', '```'])
    let l:id = OnesimusGuide('context')
    call assert_match('Preview inquiry fences', s:PopupText(l:id))
    call OnesimusGuideFilter(l:id, "\<Esc>")
    setlocal filetype=cogitatum
    let l:id = OnesimusGuide('context')
    call assert_match('COGITATUM INQUIRY', s:PopupText(l:id))
    call assert_match('Browser preview (F5)', s:PopupText(l:id))
    call assert_match('Terminal Reading (saved file)', s:PopupText(l:id))
    call assert_match('Outline / names', s:PopupText(l:id))
    call assert_match('Inquiry problems', s:PopupText(l:id))
    call OnesimusGuideFilter(l:id, 'o')
    call assert_match('Terminal Map (saved file)', s:PopupText(l:id))
    call assert_match('Stop browser preview', s:PopupText(l:id))
    call OnesimusGuideFilter(l:id, "\<Esc>")
  endif

  let l:focus_state = copy(g:onesimus_wordproc_state)
  let g:onesimus_wordproc_state = {'winid': win_getid()}
  let l:id = OnesimusGuide('context')
  call assert_match('Leave focus mode', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, "\<Esc>")
  setlocal filetype=
  let l:id = OnesimusGuide('context')
  call assert_match('WRITING', s:PopupText(l:id),
        \ 'focus mode gives an untyped draft a writing menu')
  call assert_match('Word count', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, "\<Esc>")
  let g:onesimus_wordproc_state = l:focus_state

  setlocal filetype=text
  let l:id = OnesimusGuide('context')
  call assert_match('WRITING', s:PopupText(l:id))
  call assert_match('Save text', s:PopupText(l:id))
  call assert_notmatch('Preview\|Compile\|Buffer symbols', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, "\<Esc>")

  enew
  file /tmp/onesimus-guide.bib
  setlocal filetype=bib
  let l:id = OnesimusGuide('context')
  call assert_match('BIBLIOGRAPHY', s:PopupText(l:id))
  call assert_match('Save bibliography', s:PopupText(l:id))
  call assert_match('Compare with disk', s:PopupText(l:id))
  call assert_match('Format text (F6)', s:PopupText(l:id),
        \ 'bibliography keeps its formatter in the flat menu')
  call assert_notmatch('Sentence lines\|math symbols\|build PDF\|Word count',
        \ s:PopupText(l:id))
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
  execute 'source '.fnameescape($VIMRCDIR.'/functions/Guide.vim')
  let l:next_notice = OnesimusNotify('NEXT NOTICE', ['result'], 1)
  call assert_equal({}, popup_getpos(l:notice),
        \ 'a new result replaces its notification even across config reloads')
  call assert_match('NEXT NOTICE', s:PopupText(l:next_notice))
  call assert_match('NOTICE TEST\ncompleted', execute('messages'),
        \ 'replaced notifications remain available in messages')
  call popup_close(l:next_notice)

  " Exercise the old-Vim renderer even though this test Vim has popup support.
  let l:sid = s:GuideScriptID()
  call assert_true(l:sid > 0)
  let v:errmsg = ''
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
