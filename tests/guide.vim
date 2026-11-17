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
  " \ is the global menu and \\ the file menu; every row is a real mapping.
  call assert_match('One<CR>', maparg('\', 'n'))
  call assert_match("OnesimusGuide('context')", maparg('<leader><leader>', 'n'))
  call assert_match('One indent', maparg('<leader>ti', 'n'))
  call assert_match('One parens', maparg('<leader>tp', 'n'))
  call assert_match('One background', maparg('<leader>tb', 'n'))
  call assert_match('One health', maparg('<leader>oi', 'n'))
  call assert_match('One build', maparg('<F5>', 'n'))
  call assert_match("one#key('b')", maparg('<leader><leader>b', 'n'))
  call assert_equal('', maparg('<leader>.', 'n'), 'the old file-menu entry is gone')
  call assert_equal(['health'], one#complete('hea', 'One hea', 7))
  call assert_equal(['enable', 'install'], one#complete('', 'One jieba ', 10))

  let l:id = OnesimusGuide()
  let l:root = s:PopupText(l:id)
  call assert_match('ACTIONS', l:root)
  call assert_match('\\\s\+This file', l:root)
  call assert_match('f\s\+Find', l:root)
  call assert_match('g\s\+Git', l:root)
  call assert_match('t\s\+Toggle', l:root)
  call assert_match('o\s\+Onesimus', l:root)
  call assert_match('?\s\+Manual', l:root)

  call OnesimusGuideFilter(l:id, 't')
  call assert_match('Redraw screen.*Ctrl-L', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, "\<BS>")
  call assert_match('ACTIONS', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, 'f')
  let l:find = s:PopupText(l:id)
  call assert_match('Files', l:find)
  call assert_match('Buffers', l:find)
  call assert_match('Search project', l:find)
  call OnesimusGuideFilter(l:id, "\<Esc>")

  let l:id = OnesimusGuide()
  call OnesimusGuideFilter(l:id, 'o')
  call assert_match('Update', s:PopupText(l:id))
  call assert_match('Usage', s:PopupText(l:id))
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
  call assert_match('b\s\+Build & show', l:code)
  call assert_match('t\s\+Outline', l:code)
  call assert_notmatch('Word count\|Spelling', l:code,
        \ 'writing actions stay out of code buffers')
  call OnesimusGuideFilter(l:id, "\<Esc>")

  doautocmd User ALELSPStarted
  call assert_equal('', maparg('gi', 'n'),
        \ 'LSP integration preserves Vim''s last-insert command')
  call assert_equal('', maparg('gt', 'n'),
        \ 'LSP integration preserves Vim''s next-tab command')
  let b:onesimus_lsp_ready = 0
  let v:errmsg = ''
  call assert_false(OnesimusLSPNavigate('implementation'))
  call assert_equal('', v:errmsg,
        \ 'navigation without a server is a friendly no-op')
  let b:onesimus_lsp_ready = 1
  let l:id = OnesimusGuide('context')
  call assert_match('n\s\+Rename symbol', s:PopupText(l:id))
  call assert_match('a\s\+Code action', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, "\<Esc>")
  silent! delcommand ALEGoToImplementation
  command! ALEGoToImplementation let g:onesimus_test_navigation = 'implementation'
  One goto implementation
  call assert_equal('implementation', g:onesimus_test_navigation)

  " A letter keeps its meaning across filetypes: typed \\b reaches the
  " implementation registered for this buffer's filetype.
  enew
  setlocal filetype=guidetest
  let g:onesimus_guide_ran = ''
  call one#define('build', 'guidetest', {-> execute('let g:onesimus_guide_ran = "build"')})
  call one#define('sentences', 'guidetest', {-> execute('let g:onesimus_guide_ran = "sentences"')})
  call feedkeys('\\b', 'xt')
  call assert_equal('build', g:onesimus_guide_ran, 'typed \\b runs this filetype''s build')
  let l:id = OnesimusGuide('context')
  call OnesimusGuideFilter(l:id, 'l')
  call feedkeys('', 'x')
  call assert_equal('sentences', g:onesimus_guide_ran, 'menu letters run the same verbs')
  call feedkeys('\\v', 'xt')
  call assert_match('\\\\v is not available', execute('1messages'))

  enew
  setlocal filetype=tex
  call assert_match('^No unsaved edits', OnesimusTexMenuSummary(),
        \ 'an untouched unnamed buffer must not claim it has been saved')
  file /tmp/onesimus-guide.tex
  call setline(1, 'A modified TeX buffer.')
  setlocal filetype=tex
  call feedkeys('\\', 'xt')
  call assert_match('TEX PAPER', s:PopupText(popup_list()[-1]),
        \ 'a pause after \\ shows the file menu')
  call popup_close(popup_list()[-1])
  let l:id = OnesimusGuide()
  call assert_match('This file · TeX paper', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, '\')
  let l:tex = s:PopupText(l:id)
  call assert_match('TEX PAPER', l:tex)
  call assert_match('Unsaved', l:tex)
  for l:row in ['b\s\+Build & show  (F5)', 'v\s\+Show cursor in preview',
        \ 's\s\+Save safely', 'e\s\+Problems', 't\s\+Outline',
        \ 'd\s\+Show changes', 'w\s\+Word count', 'l\s\+One sentence per line']
    call assert_match(l:row, l:tex)
  endfor
  call assert_match('<.*Back', getbufline(winbufnr(l:id), 3)[0])
  call assert_match('↑↓ select.*Enter/tap', l:tex)
  call assert_equal('a', &mouse)
  call assert_equal('button', popup_getoptions(l:id).close)
  call OnesimusGuideFilter(l:id, "\<Down>")
  call assert_match('^> v', getbufline(winbufnr(l:id), 5)[0])
  if exists('*test_setmouse')
    redraw
    let l:pos = popup_getpos(l:id)
    call test_setmouse(l:pos.core_line + 3 - l:pos.firstline, l:pos.core_col + 2)
    call OnesimusGuideFilter(l:id, "\<LeftMouse>")
    call assert_match('TEX PAPER', s:PopupText(l:id), 'touch press alone never activates Back')
    call OnesimusGuideFilter(l:id, "\<LeftRelease>")
    call assert_match('ACTIONS', s:PopupText(l:id), 'release activates Back')
  else
    call OnesimusGuideFilter(l:id, "\<Left>")
  endif
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
    let l:position = popup_getpos(l:id)
    call assert_true(l:position.firstline > 1,
          \ 'touch/wheel selection remains visible on a short terminal')
    call assert_true(l:position.width <= &columns)
    let l:selected_line = match(getbufline(winbufnr(l:id), 1, '$'), '^> ') + 1
    call assert_true(l:selected_line > 0
          \ && l:position.firstline <= l:selected_line
          \ && l:position.firstline + l:position.core_height > l:selected_line,
          \ 'the selected row is visible before Enter can run it: '.string(l:position))
    call assert_false(popup_getoptions(l:id).wrap,
          \ 'short menu labels do not become multi-row touch targets')
    call OnesimusGuideFilter(l:id, "\<Esc>")
  finally
    let &lines = l:saved_lines
    let &columns = l:saved_columns
  endtry

  enew
  call setline(1, 'An ASCII Markdown buffer.')
  setfiletype markdown
  let l:id = OnesimusGuide('context')
  let l:prose = s:PopupText(l:id)
  call assert_match('MARKDOWN', l:prose)
  call assert_match('v\s\+Show cursor in preview', l:prose)
  call assert_match('w\s\+Word count', l:prose)
  call assert_match('p\s\+Spelling marks', l:prose)
  call assert_match('z\s\+Focus mode', l:prose)
  call assert_notmatch('Inquiry\|Terminal Reading', l:prose,
        \ 'Cogitatum actions need cog fences')
  call OnesimusGuideFilter(l:id, "\<Esc>")

  if exists(':CogRead') == 2
    call setline(1, ['```cog', '- [C] A claim.', '```'])
    let l:id = OnesimusGuide('context')
    call assert_match('i\s\+Preview inquiry fences', s:PopupText(l:id))
    call assert_match('r\s\+Terminal Reading', s:PopupText(l:id))
    call OnesimusGuideFilter(l:id, "\<Esc>")
    setlocal filetype=cogitatum
    let l:id = OnesimusGuide('context')
    call assert_match('COGITATUM INQUIRY', s:PopupText(l:id))
    call assert_match('c\s\+Terminal Map', s:PopupText(l:id))
    call OnesimusGuideFilter(l:id, "\<Esc>")
  endif

  setlocal filetype=text
  let l:id = OnesimusGuide('context')
  call assert_match('WRITING', s:PopupText(l:id))
  call assert_match('s\s\+Save safely', s:PopupText(l:id))
  call assert_notmatch('preview\|Build', s:PopupText(l:id),
        \ 'plain text has nothing to build or preview')
  call OnesimusGuideFilter(l:id, "\<Esc>")

  enew
  file /tmp/onesimus-guide.bib
  setlocal filetype=bib
  let l:id = OnesimusGuide('context')
  call assert_match('BIBLIOGRAPHY', s:PopupText(l:id))
  call assert_match('s\s\+Save safely', s:PopupText(l:id))
  call assert_notmatch('Word count\|Spelling\|One sentence', s:PopupText(l:id))
  call OnesimusGuideFilter(l:id, "\<Esc>")

  setlocal filetype=python
  One health
  let l:popups = popup_list()
  call assert_false(empty(l:popups))
  let l:health = s:PopupText(l:popups[-1])
  call assert_match('TOOL STATUS', l:health)
  call assert_match('Filetype  python', l:health)
  call assert_match('Details.*:ALEInfo', l:health)
  call OnesimusPopupFilter(l:popups[-1], 'q')

  let l:saved_jieba_error = get(g:, 'onesimus_jieba_error', '')
  let g:onesimus_jieba_error = 'synthetic backend failure'
  One health
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
