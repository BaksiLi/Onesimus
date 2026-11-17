" Focus mode must be reversible and safe when lazy plugins are absent.
" Run with:
"   vim -Nu tests/wordproc.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

function! s:CloseWritingPopups() abort
  for l:id in popup_list()
    call popup_close(l:id)
  endfor
endfunction

function! s:RunWritingActionTests() abort
  let l:fixture = tempname()
  call mkdir(l:fixture, 'p')
  let l:draft = l:fixture.'/draft.md'
  let l:other = l:fixture.'/other.txt'
  let l:bib = l:fixture.'/refs.bib'
  let l:tex = l:fixture.'/paper.tex'
  let l:empty = l:fixture.'/empty.txt'
  call writefile(['Original draft.'], l:draft)
  call writefile(['Original other.'], l:other)
  call writefile(['@article{original, title={Original}}'], l:bib)
  call writefile(['A TeX sentence.'], l:tex)
  try
    execute 'edit '.fnameescape(l:empty)
    setlocal filetype=text
    call assert_false(&l:modified)
    call assert_true(OnesimusWritingSave())
    call assert_true(filereadable(l:empty),
          \ 'explicit save also creates an untouched named draft')
    call assert_false(&l:modified)
    call s:CloseWritingPopups()
    execute 'edit '.fnameescape(l:other)
    call setline(1, 'Unsaved other.')
    execute 'edit '.fnameescape(l:draft)
    setlocal filetype=markdown
    call setline(1, 'Three simple words.')
    let l:tick = b:changedtick
    let l:modified = &l:modified
    call assert_true(OnesimusWritingCountWords())
    let l:count_popup = popup_list()[-1]
    let l:count_text = join(getbufline(winbufnr(l:count_popup), 1, '$'), "\n")
    call assert_match('3 words', l:count_text)
    call assert_match('Source count.*markup.*CJK', l:count_text)
    call assert_equal(l:tick, b:changedtick)
    call assert_equal(l:modified, &l:modified)
    call assert_equal(['Original draft.'], readfile(l:draft),
          \ 'counting includes unsaved edits without saving them')
    call s:CloseWritingPopups()

    if has('spell')
      setlocal nospell spelllang=en
      call assert_true(OnesimusWritingToggleSpell())
      call assert_true(&l:spell)
      call assert_true(OnesimusWritingToggleSpell())
      call assert_false(&l:spell)
      call assert_equal(l:tick, b:changedtick)
      call assert_equal(l:modified, &l:modified)
      call assert_equal(['Original draft.'], readfile(l:draft),
            \ 'spelling toggles change display only')
      setlocal spell
      call assert_true(OnesimusWritingToggleSpell(),
            \ 'spelling marks can always be hidden')
      call assert_false(&l:spell)
      call setline(1, 'Three simple words.')
    endif
    call assert_true(OnesimusWritingSave())
    call assert_false(&l:modified)
    call assert_equal(['Three simple words.'], readfile(l:draft))
    call assert_equal(['Original other.'], readfile(l:other),
          \ 'save writes this draft only, not another dirty buffer')
    call assert_true(getbufvar(bufnr(l:other), '&modified'))

    call setline(1, 'Read-only edit.')
    setlocal readonly
    call assert_false(OnesimusWritingSave(),
          \ 'writing save never forces a read-only file')
    call assert_equal(['Three simple words.'], readfile(l:draft))
    call assert_true(&l:modified)
    setlocal noreadonly

    execute 'edit '.fnameescape(l:bib)
    setlocal filetype=bib
    call setline(1, '@article{saved, title={Saved}}')
    call assert_true(OnesimusWritingSave())
    call assert_equal(['@article{saved, title={Saved}}'], readfile(l:bib))
    call setline(1, '@article{local, title={Local}}')
    call writefile(['@article{collaborator, title={Disk}}'], l:bib)
    call assert_false(OnesimusWritingSave(),
          \ 'bibliography saving uses the shared conflict guard')
    call assert_equal(['@article{collaborator, title={Disk}}'], readfile(l:bib))
    call assert_true(&l:modified)

    execute 'edit '.fnameescape(l:tex)
    setlocal filetype=tex
    call setline(1, 'An explicitly saved TeX sentence.')
    call assert_true(OnesimusWritingSave())
    call assert_equal(['An explicitly saved TeX sentence.'], readfile(l:tex))
    call assert_false(&l:modified)

    " The same content-based collaboration rules protect every writing host.
    " Equal-length revisions exercise the shared content fingerprint.
    for [l:extension, l:filetype] in [['md', 'markdown'], ['txt', 'text'],
          \ ['cog.md', 'cogitatum']]
      let l:path = l:fixture.'/shared.'.l:extension
      call writefile(['Original.'], l:path)
      execute 'edit '.fnameescape(l:path)
      execute 'setlocal filetype='.l:filetype
      call writefile(['External.'], l:path)
      call assert_true(OnesimusCheckExternalChanges(0))
      call assert_equal(['External.'], getline(1, '$'), l:filetype.' clean refresh')
      call setline(1, 'My draft.')
      call writefile(['New disk.'], l:path)
      call assert_false(OnesimusWritingSave(), l:filetype.' protects both revisions')
      call assert_equal(['My draft.'], getline(1, '$'))
      call assert_equal(['New disk.'], readfile(l:path))
      let l:id = OnesimusGuide('context')
      call assert_match('DISK CONFLICT', join(getbufline(winbufnr(l:id), 1, '$'), "\n"))
      call assert_notmatch('Browser preview', join(getbufline(winbufnr(l:id), 1, '$'), "\n"),
            \ 'a conflict shows resolution actions in every writing filetype')
      call popup_close(l:id)
      bwipeout!
    endfor

    enew
    setlocal filetype=text
    call setline(1, 'An unnamed draft.')
    call assert_false(OnesimusWritingSave())
    call assert_true(&l:modified)
    call setline(1, '')
    setlocal buftype=nofile
    call assert_false(OnesimusWritingCountWords())
    call assert_false(OnesimusWritingToggleSpell())
    setlocal buftype= filetype=python
    call assert_false(OnesimusWritingSave())
    call assert_false(OnesimusWritingCountWords())
    call assert_true(OnesimusWritingHelp())
  finally
    call s:CloseWritingPopups()
    for l:path in [l:draft, l:other, l:bib, l:tex, l:empty]
      if bufexists(l:path)
        execute 'bwipeout! '.bufnr(l:path)
      endif
    endfor
    enew!
    call delete(l:fixture, 'rf')
  endtry
endfunction

function! s:RunWordProcTests() abort
  let g:gitgutter_enabled = 0
  let l:number = &l:number
  let l:textwidth = &l:textwidth

  One focus
  call assert_false(empty(g:onesimus_wordproc_state))
  call assert_true(OnesimusWritingFocusActive())
  One focus
  call assert_equal({}, g:onesimus_wordproc_state)
  call assert_false(OnesimusWritingFocusActive())
  call assert_equal(0, g:gitgutter_enabled,
        \ 'focus mode preserves an already disabled GitGutter')
  call assert_equal(l:number, &l:number)
  call assert_equal(l:textwidth, &l:textwidth)

  if PlugInstalled('goyo.vim') && exists(':Goyo')
    silent Goyo
    call assert_true(exists('t:goyo_revert'))
    One focus
    call assert_true(exists('t:goyo_revert'),
          \ 'focus mode leaves a pre-existing Goyo session active')
    One focus
    call assert_true(exists('t:goyo_revert'),
          \ 'leaving focus mode does not close user-owned Goyo')
    silent! Goyo!
  endif

  if PlugInstalled('limelight.vim') && exists(':Limelight')
    silent Limelight
    call assert_true(exists('#limelight'))
    One focus
    call assert_true(exists('#limelight'),
          \ 'focus mode leaves a pre-existing Limelight session active')
    One focus
    call assert_true(exists('#limelight'),
          \ 'leaving focus mode does not close user-owned Limelight')
    silent! Limelight!
  endif

  let l:goyo_dir = g:plugs['goyo.vim'].dir
  let l:limelight_dir = g:plugs['limelight.vim'].dir
  let g:plugs['goyo.vim'].dir = '/tmp/onesimus-plugin-not-installed'
  let g:plugs['limelight.vim'].dir = '/tmp/onesimus-plugin-not-installed'
  setlocal number relativenumber cursorline textwidth=72 nowrap nolinebreak nospell
  let l:tick = b:changedtick
  let v:errmsg = ''
  One focus
  call assert_equal(72, &l:textwidth,
        \ 'focus owns display only, never a buffer formatting policy')
  call assert_true(&l:wrap)
  call assert_true(&l:linebreak)
  setlocal spell textwidth=91
  One focus
  call assert_equal(91, &l:textwidth,
        \ 'an explicit formatting-policy change during focus survives exit')
  call assert_false(&l:wrap)
  call assert_false(&l:linebreak)
  call assert_true(&l:spell, 'spelling is independent of focus mode')
  call assert_true(&l:number)
  call assert_true(&l:relativenumber)
  call assert_true(&l:cursorline)
  call assert_equal(l:tick, b:changedtick,
        \ 'focus mode and restoring its options never edit the draft')
  call assert_notmatch('E492:', v:errmsg,
        \ 'missing focus plugins use the native fallback')
  let g:plugs['goyo.vim'].dir = l:goyo_dir
  let g:plugs['limelight.vim'].dir = l:limelight_dir

  " Native focus releases its view before moving to another buffer/window.
  let g:plugs['goyo.vim'].dir = '/tmp/onesimus-plugin-not-installed'
  let g:plugs['limelight.vim'].dir = '/tmp/onesimus-plugin-not-installed'
  setlocal number nowrap nolinebreak nobreakindent showbreak=OLD
  let l:owner = win_getid()
  One focus
  call assert_true(&l:breakindent)
  call assert_equal('↳ ', &l:showbreak)
  vnew
  let l:other = win_getid()
  setlocal number nowrap textwidth=93
  call assert_false(OnesimusWritingFocusActive())
  call assert_equal(l:other, win_getid(), 'focus cleanup never jumps to the owner')
  call assert_equal(93, &l:textwidth)
  call assert_false(&l:wrap)
  call assert_equal(0, getwinvar(l:owner, '&wrap'))
  call assert_equal('OLD', getwinvar(l:owner, '&showbreak'))
  close

  " Leaving a buffer restores its remembered view before it becomes hidden.
  file onesimus-focus-origin
  call setline(1, 'Draft stays unsaved.')
  let l:original = bufnr('')
  One focus
  enew
  call assert_false(OnesimusWritingFocusActive())
  setlocal textwidth=97 nowrap
  execute 'buffer '.l:original
  call assert_false(&l:wrap)
  call assert_equal('OLD', &l:showbreak)
  let g:plugs['goyo.vim'].dir = l:goyo_dir
  let g:plugs['limelight.vim'].dir = l:limelight_dir

  if PlugInstalled('goyo.vim') && exists(':Goyo')
    let l:origin = win_getid()
    setlocal nowrap textwidth=79
    One focus
    call assert_true(&l:wrap, 'plugin and native focus use the same soft view')
    call assert_equal(79, &l:textwidth)
    silent Goyo!
    call assert_false(OnesimusWritingFocusActive(),
          \ 'external Goyo exit also releases focus ownership')
    call assert_equal(l:origin, win_getid())
    call assert_false(&l:wrap, 'temporary Goyo view did not alter the origin')
    call assert_equal(79, &l:textwidth)
    One focus
    tabprevious
    call assert_false(OnesimusWritingFocusActive(),
          \ 'Goyo automatic TabLeave exit also releases focus ownership')
    call assert_equal(l:origin, win_getid())
    call assert_false(&l:wrap)
  endif

  call s:RunWritingActionTests()

  call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors,
        \ '/tmp/onesimus-wordproc-result')
  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_wordproc_test
  autocmd!
  autocmd VimEnter * ++nested call <SID>RunWordProcTests()
augroup END
