" TeX persistence/build UX must preserve both sides of an external conflict.
" Run with: vim -Nu tests/tex_workflow.vim -i NONE -n -es -c "call OnesimusRunTeXTests()"

let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let s:fixture = tempname().' TeX path $semi; quote'''
call mkdir(s:fixture, 'p')
let $XDG_STATE_HOME = s:fixture.'/state'
let g:vimtex_cache_root = s:fixture.'/cache'

let $VIMRCDIR = s:root
let $MYVIMDOT = s:root.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
let g:vimtex_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

let g:onesimus_tex_compile_once_calls = 0
let g:onesimus_tex_compile_live_calls = 0
let g:onesimus_tex_stop_calls = 0
let g:onesimus_tex_sentence_runner_calls = 0
let g:onesimus_tex_browser_opens = []

function! OnesimusOpenBrowser(url) abort
  call add(g:onesimus_tex_browser_opens, a:url)
  return 1
endfunction

function! s:CompilerRunning() dict abort
  return get(self, 'running', 0)
endfunction

function! s:Compileable() dict abort
  return 1
endfunction

function! s:CompileOnce() abort
  let g:onesimus_tex_compile_once_calls += 1
  let b:vimtex.compiler.running = 1
  let b:vimtex.compiler.status = 1
endfunction

function! s:CompileLive() abort
  let g:onesimus_tex_compile_live_calls += 1
  let b:vimtex.compiler.running = 1
  let b:vimtex.compiler.status = 1
endfunction

function! s:StopCompile() abort
  let g:onesimus_tex_stop_calls += 1
  let b:vimtex.compiler.running = 0
  let b:vimtex.compiler.status = 0
endfunction

function! s:SentenceRunner(text, config) abort
  let g:onesimus_tex_sentence_runner_calls += 1
  call assert_match('First sentence\. Second sentence\.', a:text)
  call assert_match('manipulateSentences: 1', join(readfile(a:config), "\n"))
  return {'status': 0, 'output': "First sentence.\nSecond sentence.\n"}
endfunction

function! s:FailedSentenceRunner(text, config) abort
  let g:onesimus_tex_sentence_runner_calls += 1
  return {'status': 2, 'output': 'synthetic latexindent dependency failure'}
endfunction

function! s:StubVimtex() abort
  for l:command in ['VimtexCompileSS', 'VimtexCompile', 'VimtexStop']
    if exists(':'.l:command) == 2
      execute 'delcommand '.l:command
    endif
  endfor
  command! -buffer -nargs=* VimtexCompileSS call <SID>CompileOnce()
  command! -buffer -nargs=* VimtexCompile call <SID>CompileLive()
  command! -buffer VimtexStop call <SID>StopCompile()
endfunction

function! s:Open(name, lines) abort
  let l:path = s:fixture.'/'.a:name
  call writefile(a:lines, l:path)
  execute 'edit '.fnameescape(l:path)
  setfiletype tex
  let b:vimtex_id = bufnr('%')
  let b:vimtex = {'tex': l:path, 'root': s:fixture, 'packages': {}, 'documentclass': 'article',
        \ 'is_compileable': function('<SID>Compileable')}
  let b:vimtex.compiler = {
        \ 'enabled': v:true, 'continuous': 1, 'running': 0, 'status': -1,
        \ 'name': 'test', 'is_running': function('<SID>CompilerRunning'),
        \ }
  call s:StubVimtex()
  call OnesimusRecordDiskBaseline(bufnr('%'))
  return l:path
endfunction

function! s:TestF5SafeSaveThenBuild() abort
  let l:path = s:Open('safe source.tex', ['disk base'])
  call setline(1, 'local revision')
  call assert_true(&l:modified)
  let g:onesimus_tex_compile_once_calls = 0
  silent CompileRun
  call assert_equal(['local revision'], readfile(l:path))
  call assert_false(&l:modified)
  call assert_equal(1, g:onesimus_tex_compile_once_calls)
  call assert_match('TeX BUILDING ONCE', OnesimusTexStatusline())
endfunction

function! s:TestAlternateTeXExtensionKeepsBaseline() abort
  let l:path = s:Open('chapter.ltx', ['first disk revision'])
  let g:onesimus_tex_compile_once_calls = 0
  let g:onesimus_tex_stop_calls = 0
  call setline(1, 'first local revision')
  silent CompileRun
  call assert_equal(['first local revision'], readfile(l:path))
  call assert_false(OnesimusDiskChanged())

  call setline(1, 'second local revision')
  silent CompileRun
  call assert_equal(['second local revision'], readfile(l:path))
  call assert_false(OnesimusHasExternalConflict())
  call assert_equal(2, g:onesimus_tex_compile_once_calls)
  call assert_equal(1, g:onesimus_tex_stop_calls,
        \ 'a second F5 replaces an older one-shot with the newest source')
endfunction

function! s:TestUnavailableCompilerDoesNotSave() abort
  let l:path = s:Open('no compiler.tex', ['disk base'])
  call setline(1, 'local unsaved revision')
  let b:vimtex.compiler.enabled = v:false
  let g:onesimus_tex_compile_once_calls = 0
  silent CompileRun
  call assert_equal(['disk base'], readfile(l:path))
  call assert_equal(['local unsaved revision'], getline(1, '$'))
  call assert_true(&l:modified)
  call assert_equal(0, g:onesimus_tex_compile_once_calls)
endfunction

function! s:TestMissingVimtexDoesNotSave() abort
  let l:path = s:Open('no VimTeX.tex', ['disk base'])
  call setline(1, 'local unsaved revision')
  delcommand VimtexCompileSS
  let g:onesimus_tex_compile_once_calls = 0
  silent CompileRun
  call assert_equal(['disk base'], readfile(l:path))
  call assert_true(&l:modified)
  call assert_equal(0, g:onesimus_tex_compile_once_calls)
endfunction

function! s:TestUnavailableLiveModeDoesNotSave() abort
  let l:path = s:Open('one shot backend.tex', ['disk base'])
  call setline(1, 'local unsaved revision')
  let b:vimtex.compiler.continuous = 0
  call assert_false(OnesimusTexToggleLiveBuild())
  call assert_equal(['disk base'], readfile(l:path))
  call assert_true(&l:modified)
endfunction

function! s:TestMissingWritingAndViewerToolsAreFriendly() abort
  let l:path = s:Open('missing optional tools.tex', ['disk base'])
  call assert_false(OnesimusTexView(), 'viewing before a PDF exists is an actionable no-op')
  let l:path_value = $PATH
  try
    command! -buffer VimtexCountWords
          \ let g:onesimus_unexpected_word_count = 1
    let $PATH = ''
    call assert_false(OnesimusTexCountWords(),
          \ 'missing texcount degrades without a raw command error')
    call assert_false(get(g:, 'onesimus_unexpected_word_count', 0))
  finally
    let $PATH = l:path_value
  endtry
endfunction

function! s:TestBrowserViewAndFeedbackNeverSave() abort
  let l:path = s:Open('Browser paper & notes.tex', ['saved source'])
  let l:ssh = $SSH_CONNECTION
  let $SSH_CONNECTION = 'synthetic remote session'
  try
    call writefile(['%PDF-1.4', 'fixture', '%%EOF'], fnamemodify(l:path, ':r').'.pdf')
    call setline(1, 'unsaved new sentence')
    let l:tick = b:changedtick
    let l:builds = g:onesimus_tex_compile_once_calls
    let l:opens = len(g:onesimus_tex_browser_opens)
    call assert_true(OnesimusTexView(), 'an unsaved buffer can read the last built PDF')
    for l:attempt in range(100)
      if execute('messages') =~# 'Locate in source: tap' | break | endif
      sleep 20m
    endfor
    let l:url = matchstr(execute('messages'), 'http://127\.0\.0\.1:\d\+/[^ /'."\n".']*/')
    call assert_false(empty(l:url), 'the reader publishes a loopback URL')
    call assert_equal([l:url], g:onesimus_tex_browser_opens[l:opens :])
    call assert_match('Built PDF; unsaved edits are absent', execute('messages'))
    call assert_true(OnesimusTexView())
    call assert_match(escape(l:url, '.\/'), execute('messages'), 'reopening reuses the owned reader')
    call assert_equal([l:url, l:url], g:onesimus_tex_browser_opens[l:opens :],
          \ 'explicit preview must open the browser even when its reader already runs')
    let b:vimtex.compiler.onesimus_build_mode = 'once'
    call OnesimusTexBuildFeedback('success')
    call assert_equal(l:opens + 2, len(g:onesimus_tex_browser_opens),
          \ 'a background build never raises the browser')
    let b:vimtex.compiler.onesimus_open_after_build = 1
    call OnesimusTexBuildFeedback('success')
    call assert_false(b:vimtex.compiler.onesimus_open_after_build, 'successful build consumes the open request')
    for l:attempt in range(100)
      if len(g:onesimus_tex_browser_opens) == l:opens + 3 | break | endif
      sleep 20m
    endfor
    call assert_equal([l:url, l:url, l:url], g:onesimus_tex_browser_opens[l:opens :],
          \ 'F5 opens the existing URL when no browser page is present')
    call system('python3 -c '.shellescape(
          \ 'import sys,urllib.request; urllib.request.urlopen(sys.argv[1]).read()')
          \ .' '.shellescape(l:url.'state?client=workflow'))
    call assert_equal(0, v:shell_error)
    let b:vimtex.compiler.onesimus_open_after_build = 1
    call OnesimusTexBuildFeedback('success')
    sleep 200m
    call assert_equal(l:opens + 3, len(g:onesimus_tex_browser_opens),
          \ 'F5 must not launch a second browser when a page is reading the session')
    let b:vimtex.compiler.onesimus_open_after_build = 1
    call OnesimusTexBuildFeedback('failed')
    call assert_false(b:vimtex.compiler.onesimus_open_after_build, 'failed build consumes the request without opening')
    call assert_equal(l:opens + 3, len(g:onesimus_tex_browser_opens))
    call assert_equal(l:builds, g:onesimus_tex_compile_once_calls)
    call assert_equal(l:tick, b:changedtick)
    call assert_true(&modified)
    call assert_equal(['saved source'], readfile(l:path))
    call OnesimusTexStatus()
    let l:text = join(getbufline(winbufnr(popup_list()[-1]), 1, '$'), "\n")
    call assert_match('browser PDF', l:text)
    call assert_notmatch('Skim\|Preview (PDF', l:text)
    let l:notices = sort(popup_list())
    call delete(fnamemodify(l:path, ':r').'.pdf')
    for l:attempt in range(200)
      if execute('messages') =~# 'PDF reader: .*No such file' | break | endif
      sleep 20m
    endfor
    call assert_match('PDF reader: .*No such file', execute('messages'))
    call assert_equal(l:notices, sort(popup_list()), 'stderr diagnostics do not create popups')
    call assert_true(OnesimusTexView(), 'an existing reader retains its last complete PDF after a failed build')
    call assert_equal([l:url, l:url, l:url, l:url], g:onesimus_tex_browser_opens[l:opens :],
          \ 'a missing build output must not block opening the retained PDF')
  finally
    call OnesimusTexBrowserStop()
    let $SSH_CONNECTION = l:ssh
    for l:id in popup_list() | call popup_close(l:id) | endfor
  endtry
endfunction

function! s:TestRevisionNeverSavesAnUnsavedDraft() abort
  let l:path = s:Open('revision draft.tex', ['saved source'])
  call writefile(['%PDF-1.4', 'fixture', '%%EOF'], fnamemodify(l:path, ':r').'.pdf')
  call setline(1, 'unsaved draft')
  let l:tick = b:changedtick
  call assert_false(OnesimusDiff('HEAD'))
  call assert_true(&modified)
  call assert_equal(l:tick, b:changedtick)
  call assert_equal(['saved source'], readfile(l:path))
  call assert_equal(2, exists(':OnesimusDiff'))
  call assert_equal(0, exists(':OnesimusTexDiffBase'), 'the old overlay entry is removed')
endfunction

function! s:TestSentenceLinesStayUnsavedAndUndoable() abort
  let l:path = s:Open('sentence migration.tex',
        \ ['First sentence. Second sentence.'])
  let l:disk = readfile(l:path)
  let g:onesimus_tex_sentence_runner_calls = 0
  let g:OnesimusTexSentenceFormatterRunner = function('<SID>SentenceRunner')
  try
    call assert_true(OnesimusTexSentenceLines())
    call assert_equal(['First sentence.', 'Second sentence.'], getline(1, '$'))
    call assert_equal(l:disk, readfile(l:path),
          \ 'sentence migration changes only the Vim buffer')
    call assert_true(&l:modified)
    call assert_equal(1, g:onesimus_tex_sentence_runner_calls)
    silent undo
    call assert_equal(['First sentence. Second sentence.'], getline(1, '$'),
          \ 'one undo restores the pre-migration source')
  finally
    unlet! g:OnesimusTexSentenceFormatterRunner
  endtry
endfunction

function! s:TestRealSentenceCommandUsesStdinAndOwnUndoBlock() abort
  if has('win32') || has('win64')
    return
  endif
  let l:path = s:Open('sentence command.tex', ['Disk sentence.'])
  call setline(1, 'Edited first sentence. Second sentence.')
  let l:before_format = getline(1, '$')
  let l:fake = s:fixture.'/fake latexindent'
  let l:args = s:fixture.'/sentence command args'
  let l:stdin = s:fixture.'/sentence command stdin'
  let l:config = s:fixture.'/sentence profile.yaml'
  call writefile(readfile(s:root.'/config/latexindent-sentences.yaml'), l:config)
  call writefile([
        \ '#!/bin/sh',
        \ 'if [ "$1" = "--version" ]; then',
        \ '  printf "%s\\n" "latexindent fake 1.0"',
        \ '  exit 0',
        \ 'fi',
        \ ': > "$ONESIMUS_SENTENCE_ARGS"',
        \ 'last=""',
        \ 'config=""',
        \ 'for arg in "$@"; do',
        \ '  printf "%s\\n" "$arg" >> "$ONESIMUS_SENTENCE_ARGS"',
        \ '  last="$arg"',
        \ '  case "$arg" in',
        \ '    -s) printf "%s\\n" "silent mode is invalid" >&2; exit 65 ;;',
        \ '    -l=*) config=${arg#-l=} ;;',
        \ '  esac',
        \ 'done',
        \ '[ "$last" = "-" ] || { printf "%s\\n" "stdin marker missing" >&2; exit 64; }',
        \ '[ -r "$config" ] || { printf "%s\\n" "profile missing" >&2; exit 66; }',
        \ 'tee "$ONESIMUS_SENTENCE_STDIN" >/dev/null',
        \ 'printf "%s\\n" "Edited first sentence." "Second sentence."',
        \ ], l:fake)
  call setfperm(l:fake, 'rwx------')
  call assert_equal(1, executable(l:fake))

  let l:old_args = $ONESIMUS_SENTENCE_ARGS
  let l:old_stdin = $ONESIMUS_SENTENCE_STDIN
  let $ONESIMUS_SENTENCE_ARGS = l:args
  let $ONESIMUS_SENTENCE_STDIN = l:stdin
  let b:ale_tex_latexindent_executable = l:fake
  let g:onesimus_tex_sentence_config = l:config
  try
    call assert_true(OnesimusTexSentenceLines())
    call assert_equal(['Edited first sentence.', 'Second sentence.'],
          \ getline(1, '$'))
    call assert_equal(['Disk sentence.'], readfile(l:path),
          \ 'the real command pipeline remains buffer-only')
    call assert_equal(['Edited first sentence. Second sentence.'],
          \ readfile(l:stdin))
    let l:argv = readfile(l:args)
    call assert_true(index(l:argv, '-m') >= 0)
    call assert_equal(-1, index(l:argv, '-s'))
    call assert_equal('-', l:argv[-1],
          \ 'latexindent must receive the explicit stdin filename')
    call assert_true(index(l:argv, '-l='.l:config) >= 0)
    silent undo
    call assert_equal(l:before_format, getline(1, '$'),
          \ 'one undo restores the edited pre-format buffer only')
  finally
    unlet! b:ale_tex_latexindent_executable
    unlet! g:onesimus_tex_sentence_config
    let $ONESIMUS_SENTENCE_ARGS = l:old_args
    let $ONESIMUS_SENTENCE_STDIN = l:old_stdin
  endtry
endfunction

function! s:TestSentenceFailureAndConflictPreserveSource() abort
  let l:path = s:Open('sentence failure.tex', ['Disk sentence.'])
  call setline(1, 'Local sentence. Another sentence.')
  let l:local = getline(1, '$')
  let g:onesimus_tex_sentence_runner_calls = 0
  let g:OnesimusTexSentenceFormatterRunner =
        \ function('<SID>FailedSentenceRunner')
  try
    call assert_false(OnesimusTexSentenceLines())
    call assert_equal(l:local, getline(1, '$'))
    call assert_equal(['Disk sentence.'], readfile(l:path))
    call assert_equal(1, g:onesimus_tex_sentence_runner_calls)

    call writefile(['Collaborator sentence.'], l:path)
    call assert_false(OnesimusTexSentenceLines())
    call assert_equal(l:local, getline(1, '$'))
    call assert_equal(['Collaborator sentence.'], readfile(l:path))
    call assert_equal(1, g:onesimus_tex_sentence_runner_calls,
          \ 'an external conflict blocks the formatter before it starts')
  finally
    unlet! g:OnesimusTexSentenceFormatterRunner
  endtry
endfunction

function! s:TestConflictBlocksSaveAndBuild() abort
  let l:path = s:Open('conflicted source.tex', ['shared base'])
  call setline(1, 'local revision')
  call writefile(['codex revision'], l:path)
  let g:onesimus_tex_compile_once_calls = 0
  silent CompileRun
  call assert_equal(['local revision'], getline(1, '$'))
  call assert_equal(['codex revision'], readfile(l:path))
  call assert_true(&l:modified)
  call assert_true(OnesimusHasExternalConflict())
  call assert_equal(0, g:onesimus_tex_compile_once_calls)

  let l:write_error = ''
  try
    call OnesimusGuardSourceWrite(bufnr('%'))
  catch
    let l:write_error = v:exception
  endtry
  call assert_match('write blocked', l:write_error)
  call assert_equal(['codex revision'], readfile(l:path),
        \ ':write! must not bypass the guarded TeX conflict')

  let l:origin = bufnr('%')
  let l:scratch = OnesimusDiffDisk()
  call assert_true(l:scratch > 0)
  call assert_equal(['local revision'], getbufline(l:origin, 1, '$'))
  call assert_equal(['codex revision'], getbufline(l:scratch, 1, '$'))
  call assert_equal('nofile', getbufvar(l:scratch, '&buftype'))
  call assert_false(getbufvar(l:scratch, '&modifiable'))
  call assert_true(getbufvar(l:origin, '&modified'))
  close
endfunction

function! s:TestF5LatePreWriteChangeBlocksSaveAndBuild() abort
  let l:path = s:Open('late F5 conflict.tex', ['disk base'])
  call setline(1, 'local revision')
  let g:onesimus_tex_compile_once_calls = 0
  augroup onesimus_test_f5_late_writer
    autocmd!
    execute 'autocmd BufWritePre <buffer='.bufnr('%').'> '
          \ .'call writefile([''late collaborator revision''], '
          \ .string(l:path).')'
  augroup END
  try
    silent CompileRun
  finally
    augroup onesimus_test_f5_late_writer
      autocmd!
    augroup END
  endtry
  call assert_equal(['late collaborator revision'], readfile(l:path))
  call assert_equal(['local revision'], getline(1, '$'))
  call assert_true(&l:modified)
  call assert_true(OnesimusHasExternalConflict())
  call assert_equal(0, g:onesimus_tex_compile_once_calls)
endfunction

function! s:TestLatePostWriteChangeBlocksSaveAndBuild() abort
  let l:path = s:Open('late postwrite conflict.tex', ['disk base'])
  call setline(1, 'local revision')
  let g:onesimus_tex_compile_once_calls = 0
  augroup onesimus_test_postwrite_writer
    autocmd!
    execute 'autocmd BufWritePost <buffer='.bufnr('%').'> '
          \ .'call writefile([''later collaborator revision''], '
          \ .string(l:path).')'
  augroup END
  try
    call assert_false(OnesimusTexBuildOnce())
  finally
    augroup onesimus_test_postwrite_writer
      autocmd!
    augroup END
  endtry
  call assert_equal(0, g:onesimus_tex_compile_once_calls)
  call assert_equal(['later collaborator revision'], readfile(l:path))
  call assert_equal(['local revision'], getline(1, '$'))
  call assert_true(&l:modified)
  call assert_true(OnesimusHasExternalConflict())
endfunction

function! s:TestNoFinalNewlineAndBomRoundTrip() abort
  let l:noeol = s:fixture.'/no final newline.tex'
  call writefile(['base'], l:noeol, 'b')
  execute 'edit '.fnameescape(l:noeol)
  setfiletype tex
  call s:StubVimtex()
  let b:vimtex_id = bufnr('%')
  let b:vimtex = {'tex': l:noeol, 'root': s:fixture,
        \ 'is_compileable': function('<SID>Compileable')}
  let b:vimtex.compiler = {'enabled': v:true, 'continuous': 1,
        \ 'running': 0, 'status': -1, 'name': 'test',
        \ 'is_running': function('<SID>CompilerRunning')}
  call OnesimusRecordDiskBaseline(bufnr('%'))
  call setline(1, 'local')
  call assert_true(OnesimusSafeUpdate())
  call assert_equal("local\n", join(readfile(l:noeol, 'b'), "\n"))
  call assert_false(OnesimusDiskChanged())

  let l:bom = s:fixture.'/utf8 bom.tex'
  call writefile([nr2char(0xfeff).'base'], l:bom, 'b')
  execute 'edit '.fnameescape(l:bom)
  setfiletype tex
  call OnesimusRecordDiskBaseline(bufnr('%'))
  call setline(1, 'local')
  call assert_true(OnesimusSafeUpdate())
  call assert_true(&l:bomb)
  call assert_equal('file:'.sha256(nr2char(0xfeff)."local\n"),
        \ 'file:'.sha256(join(readfile(l:bom, 'b'), "\n")))
endfunction

function! s:TestUseDiskKeepsBufferIdentity() abort
  let l:path = s:Open('use disk safely.tex', ['old local'])
  let l:bufnr = bufnr('%')
  let l:name = expand('%:p')
  call writefile(['new disk first', 'new disk second'], l:path)
  call assert_true(OnesimusUseDisk())
  call assert_equal(l:bufnr, bufnr('%'))
  call assert_equal(l:name, expand('%:p'))
  call assert_equal(['new disk first', 'new disk second'], getline(1, '$'))
  call assert_false(&l:modified)
  call assert_false(OnesimusDiskChanged())
endfunction

function! s:TestDiffDiskIgnoresFileReadHooks() abort
  let l:path = s:Open('raw disk comparison.tex', ['disk base'])
  call setline(1, 'local revision')
  call writefile(['disk real'], l:path)
  call OnesimusCheckExternalChanges(0)
  augroup onesimus_test_hostile_fileread
    autocmd!
    autocmd FileReadPost *.tex call setline(1, 'plugin-mutated-view')
  augroup END
  try
    let l:scratch = OnesimusDiffDisk()
  finally
    augroup onesimus_test_hostile_fileread
      autocmd!
    augroup END
  endtry
  call assert_equal(['disk real'], getbufline(l:scratch, 1, '$'))
  execute 'bwipeout! '.l:scratch
endfunction

function! s:TestCleanExternalReload() abort
  let l:path = s:Open('clean reload.tex', ['first disk revision'])
  call writefile(['second disk revision'], l:path)
  call assert_true(OnesimusTexSave(),
        \ 'Save-only still checks and loads a clean collaborator revision')
  call assert_equal(['second disk revision'], getline(1, '$'))
  call assert_false(&l:modified)
  call assert_false(OnesimusDiskChanged())
endfunction

function! s:TestStructuralReloadRefreshesVimtexState() abort
  let l:path = s:Open('structure reload.tex',
        \ ['\documentclass{article}', '\input{old}'])
  let g:onesimus_vimtex_reload_calls = 0
  command! -buffer VimtexReloadState
        \ let g:onesimus_vimtex_reload_calls += 1
  call writefile(['\documentclass{article}', '\input{new}'], l:path)
  call assert_true(OnesimusCheckExternalChanges(0))
  call assert_equal(1, g:onesimus_vimtex_reload_calls)
  call assert_equal('\input{new}', getline(2))
endfunction

function! s:TestLocalStructuralEditBuildsAfterReload() abort
  let l:path = s:Open('local structure change.tex',
        \ ['\documentclass{article}', '\input{old}'])
  let g:onesimus_vimtex_reload_calls = 0
  let g:onesimus_tex_compile_once_calls = 0
  command! -buffer VimtexReloadState
        \ let g:onesimus_vimtex_reload_calls += 1
  call setline(2, '\input{new}')
  call assert_true(OnesimusTexBuildOnce(),
        \ 'F5 saves and reloads changed structure before starting the build')
  call assert_equal(1, g:onesimus_tex_compile_once_calls)
  call assert_equal(['\documentclass{article}', '\input{new}'], readfile(l:path))
  call assert_equal(1, g:onesimus_vimtex_reload_calls)
  call assert_false(&l:modified)
endfunction

function! s:TestSymlinkedSourceIsGuarded() abort
  let l:real = s:fixture.'/real target.tex'
  let l:link = s:fixture.'/linked source.tex'
  call writefile(['first target revision'], l:real)
  call system('ln -s '.shellescape(l:real).' '.shellescape(l:link))
  if v:shell_error != 0
    return
  endif
  execute 'edit '.fnameescape(l:link)
  setfiletype tex
  let b:vimtex_id = bufnr('%')
  let b:vimtex = {'tex': l:link, 'root': s:fixture,
        \ 'is_compileable': function('<SID>Compileable')}
  let b:vimtex.compiler = {
        \ 'enabled': v:true, 'continuous': 1, 'running': 0, 'status': -1,
        \ 'name': 'test', 'is_running': function('<SID>CompilerRunning'),
        \ }
  call s:StubVimtex()
  call OnesimusRecordDiskBaseline(bufnr('%'))

  call writefile(['second target revision'], l:real)
  call assert_true(OnesimusCheckExternalChanges(0))
  call assert_equal(['second target revision'], getline(1, '$'))
  call setline(1, 'local revision')
  call writefile(['third target revision'], l:real)
  call assert_false(OnesimusCheckExternalChanges(0))
  call assert_true(OnesimusHasExternalConflict())
  call assert_equal(['third target revision'], readfile(l:real))
endfunction

function! s:TestUnknownDirtyBaselineBlocksFirstWrite() abort
  let l:path = s:Open('unknown baseline.tex', ['disk version'])
  call setline(1, 'local version')
  unlet! b:onesimus_disk_baseline
  let l:write_error = ''
  try
    call OnesimusGuardSourceWrite(bufnr('%'))
  catch
    let l:write_error = v:exception
  endtry
  call assert_match('write blocked', l:write_error)
  call assert_equal(['disk version'], readfile(l:path))
  call assert_equal(['local version'], getline(1, '$'))
endfunction

function! s:TestDiffDiskDecodesDosLines() abort
  let l:path = s:Open('dos conflict.tex', ['shared base'])
  call setline(1, 'local revision')
  " Binary write produces one CRLF-terminated line without relying on the
  " test host's native file format.
  call writefile(["codex revision\r", ''], l:path, 'b')
  call assert_false(OnesimusCheckExternalChanges(0))
  call assert_true(OnesimusHasExternalConflict())
  let l:origin = bufnr('%')
  let l:scratch = OnesimusDiffDisk()
  call assert_equal(['codex revision'], getbufline(l:scratch, 1, '$'))
  call assert_equal(['local revision'], getbufline(l:origin, 1, '$'))
  close
endfunction

function! s:TestBangCannotBypassFingerprintGuard() abort
  let l:path = s:Open('bang guard.tex', ['disk version'])
  call setline(1, 'local version')
  let b:onesimus_disk_baseline = 'file:synthetic-stale-baseline'
  let l:write_error = ''
  try
    write!
  catch
    let l:write_error = v:exception
  endtry
  call assert_match('write blocked', l:write_error)
  call assert_equal(['disk version'], readfile(l:path))
  call assert_equal(['local version'], getline(1, '$'))
  call assert_true(&l:modified)
endfunction

function! s:TestRangeWriteCannotBypassGuard() abort
  call s:Open('range source.tex', ['first line', 'second line'])
  let l:target = s:fixture.'/existing range target.tex'
  call writefile(['do not replace'], l:target)
  let l:write_error = ''
  try
    execute '1write! '.fnameescape(l:target)
  catch
    let l:write_error = v:exception
  endtry
  call assert_match('partial or append write blocked', l:write_error)
  call assert_equal(['do not replace'], readfile(l:target))

  let l:new = s:fixture.'/new selected scratch.tex'
  execute '1write '.fnameescape(l:new)
  call assert_equal(['first line'], readfile(l:new))
endfunction

function! s:TestWriteCopyAndSaveAsKeepPathIdentity() abort
  let l:original = s:Open('write original.tex', ['disk base'])
  let l:copy = s:fixture.'/recovery copy.tex'
  let l:renamed = s:fixture.'/renamed source.tex'
  call setline(1, 'local revision')
  execute 'write '.fnameescape(l:copy)
  call assert_equal(['local revision'], readfile(l:copy))
  call assert_equal(['disk base'], readfile(l:original))
  call assert_true(&l:modified,
        \ ':write copy keeps the original buffer intentionally modified')
  call assert_false(OnesimusHasExternalConflict())

  execute 'saveas '.fnameescape(l:renamed)
  call assert_equal(fnamemodify(l:renamed, ':p'), expand('%:p'))
  call assert_equal(['local revision'], readfile(l:renamed))
  call assert_false(&l:modified)
  call assert_false(OnesimusDiskChanged())
endfunction

function! s:TestAlternateExistingObjectCannotBeOverwritten() abort
  call s:Open('alternate object source.tex', ['local source'])
  let l:dangling = s:fixture.'/dangling alternate.tex'
  call system('ln -s '.shellescape(s:fixture.'/absent target').' '
        \ .shellescape(l:dangling))
  if v:shell_error != 0
    return
  endif
  let l:error = ''
  try
    execute 'write! '.fnameescape(l:dangling)
  catch
    let l:error = v:exception
  endtry
  call assert_match('alternate TeX/Bib write target already exists', l:error)
  call assert_equal('link', getftype(l:dangling))
endfunction

function! s:TestDirtyProjectMemberBlocksWholeBuild() abort
  let l:main = s:Open('paper main.tex', ['main disk'])
  let l:main_buf = bufnr('%')
  let l:project_id = b:vimtex_id
  call setline(1, 'main local')
  let l:child = s:Open('paper child.tex', ['child disk'])
  let b:vimtex_id = l:project_id
  let b:vimtex.tex = l:main
  call setline(1, 'child local')
  execute 'buffer '.l:main_buf
  let g:onesimus_tex_compile_once_calls = 0
  silent CompileRun
  call assert_equal(['main disk'], readfile(l:main))
  call assert_equal(['child disk'], readfile(l:child))
  call assert_true(&l:modified)
  call assert_equal(0, g:onesimus_tex_compile_once_calls)
endfunction

function! s:TestBibConflictHasDiscoverableActions() abort
  let l:path = s:fixture.'/references.bib'
  call writefile(['@book{base,}'], l:path)
  execute 'edit '.fnameescape(l:path)
  setfiletype bib
  call OnesimusRecordDiskBaseline(bufnr('%'))
  call setline(1, '@book{local,}')
  call writefile(['@book{codex,}'], l:path)
  call assert_false(OnesimusCheckExternalChanges(0))
  let l:guide = OnesimusGuide('context')
  let l:text = join(getbufline(winbufnr(l:guide), 1, '$'), "\n")
  call assert_match('BIB.*DISK CONFLICT', l:text)
  call assert_match('Compare local buffer with disk', l:text)
  call assert_match('Save reviewed buffer over disk', l:text)
  call OnesimusGuideFilter(l:guide, "\<Esc>")
endfunction

function! s:TestDeletedSourceIsPreserved() abort
  let l:path = s:Open('deleted source.tex', ['preserved revision'])
  call delete(l:path)
  call assert_false(OnesimusCheckExternalChanges(0))
  call assert_true(OnesimusHasExternalConflict())
  call assert_equal(['preserved revision'], getline(1, '$'))
  call assert_false(OnesimusUseDisk())
  call assert_equal(['preserved revision'], getline(1, '$'))

  let l:guide = OnesimusGuide('context')
  let l:text = join(getbufline(winbufnr(l:guide), 1, '$'), "\n")
  call assert_match('Recreate deleted source from local buffer', l:text)
  call assert_notmatch('Compare local buffer with disk', l:text)
  call OnesimusGuideFilter(l:guide, "\<Esc>")

  let b:onesimus_reviewed_disk_fingerprint = 'missing'
  let b:onesimus_reviewed_disk_path = fnamemodify(l:path, ':p')
  call assert_true(OnesimusCommitReviewedSource())
  call assert_true(filereadable(l:path))
  if filereadable(l:path)
    call assert_equal(['preserved revision'], readfile(l:path))
  endif
  call assert_false(&l:modified)
  call assert_false(OnesimusHasExternalConflict())
endfunction

function! s:TestUnreadableSourceCannotMasqueradeAsDeleted() abort
  if has('win32') || has('win64')
    return
  endif
  let l:path = s:Open('unreadable source.tex', ['original disk'])
  call setline(1, 'local revision')
  call writefile(['external secret'], l:path)
  call setfperm(l:path, '---------')
  if filereadable(l:path)
    " Root/special filesystems may ignore mode bits; the dangerous branch is
    " not reproducible there, so restore and leave the portable suite green.
    call setfperm(l:path, 'rw-------')
    return
  endif
  try
    call assert_false(OnesimusCheckExternalChanges(0))
    call assert_true(OnesimusHasExternalConflict())
    let b:onesimus_reviewed_disk_fingerprint = 'missing'
    let b:onesimus_reviewed_disk_path = fnamemodify(l:path, ':p')
    call assert_false(OnesimusCommitReviewedSource())
    call assert_false(filereadable(l:path))
    call assert_equal(['local revision'], getline(1, '$'))
  finally
    call setfperm(l:path, 'rw-------')
  endtry
  call assert_equal(['external secret'], readfile(l:path))
endfunction

function! s:TestSyntheticPreservationReloadsWhenPathRecovers() abort
  if has('win32') || has('win64')
    return
  endif
  let l:path = s:Open('recovered readable source.tex', ['old disk'])
  call writefile(['new disk'], l:path)
  call setfperm(l:path, '---------')
  if filereadable(l:path)
    call setfperm(l:path, 'rw-------')
    return
  endif
  call assert_false(OnesimusCheckExternalChanges(0))
  call assert_true(&l:modified,
        \ 'a synthetic modified flag prevents abandoning the last readable copy')
  call setfperm(l:path, 'rw-------')
  call assert_true(OnesimusCheckExternalChanges(0))
  call assert_equal(['new disk'], getline(1, '$'))
  call assert_false(&l:modified)
  call assert_false(OnesimusHasExternalConflict())

  let l:path = s:Open('reappeared deleted source.tex', ['before deletion'])
  call delete(l:path)
  call assert_false(OnesimusCheckExternalChanges(0))
  call assert_true(&l:modified)
  call writefile(['reappeared externally'], l:path)
  call assert_true(OnesimusCheckExternalChanges(0))
  call assert_equal(['reappeared externally'], getline(1, '$'))
  call assert_false(&l:modified)
  call assert_false(OnesimusHasExternalConflict())

  let l:empty = s:fixture.'/reappeared empty source.tex'
  call writefile([], l:empty, 'b')
  execute 'edit '.fnameescape(l:empty)
  setfiletype tex
  call OnesimusRecordDiskBaseline(bufnr('%'))
  call delete(l:empty)
  call assert_false(OnesimusCheckExternalChanges(0))
  call writefile(['external from empty'], l:empty)
  call assert_true(OnesimusCheckExternalChanges(0))
  call assert_equal(['external from empty'], getline(1, '$'))
  call assert_false(&l:modified)

  let l:path = s:Open('edited while deleted.tex', ['before deletion'])
  call delete(l:path)
  call assert_false(OnesimusCheckExternalChanges(0))
  call setline(1, 'local edit while absent')
  call writefile(['external reappearance'], l:path)
  call assert_false(OnesimusCheckExternalChanges(0))
  call assert_equal(['local edit while absent'], getline(1, '$'))
  call assert_equal(['external reappearance'], readfile(l:path))
  call assert_true(&l:modified)
  call assert_true(OnesimusHasExternalConflict())
endfunction

function! s:TestRepeatedDiffReusesCurrentDiskView() abort
  let l:path = s:Open('one diff pane.tex', ['disk base'])
  call setline(1, 'local revision')
  call writefile(['disk revision'], l:path)
  call OnesimusCheckExternalChanges(0)
  let l:first = OnesimusDiffDisk()
  let l:second = OnesimusDiffDisk()
  call assert_equal(l:first, l:second)
  call assert_equal(2, winnr('$'))
  close
endfunction

function! s:TestFailedDiffDoesNotAuthorizeOverwrite() abort
  let l:path = s:Open('failed diff authorization.tex', ['disk base'])
  call setline(1, 'local revision')
  call writefile(['collaborator revision'], l:path)
  call OnesimusCheckExternalChanges(0)
  let l:width = &columns
  let l:minwidth = &winminwidth
  try
    let &columns = 60
    let &winminwidth = 20
    vsplit
    vsplit
    call assert_equal(0, OnesimusDiffDisk())
    call assert_equal('', get(b:, 'onesimus_reviewed_disk_fingerprint', ''))
  finally
    only
    let &columns = l:width
    let &winminwidth = l:minwidth
  endtry
endfunction

function! s:TestReviewedRevisionChangingAtFinalGuardIsBlocked() abort
  let l:path = s:Open('final review guard.tex', ['disk revision'])
  call setline(1, 'local revision')
  call writefile(['collaborator revision'], l:path)
  call OnesimusCheckExternalChanges(0)
  let l:scratch = OnesimusDiffDisk()
  execute 'bwipeout '.l:scratch
  call assert_true(l:scratch > 0)

  augroup onesimus_test_late_writer
    autocmd!
    execute 'autocmd BufWritePre <buffer='.bufnr('%').'> '
          \ .'call writefile([''later collaborator revision''], '
          \ .string(l:path).')'
  augroup END
  try
    call assert_false(OnesimusCommitReviewedSource())
  finally
    augroup onesimus_test_late_writer
      autocmd!
    augroup END
  endtry
  call assert_equal(['later collaborator revision'], readfile(l:path))
  call assert_equal(['local revision'], getline(1, '$'))
  call assert_true(&l:modified)
  call assert_true(OnesimusHasExternalConflict())
endfunction

function! s:TestEventAndStoragePolicy() abort
  let l:events = execute('autocmd onesimus_external_changes')
  call assert_match('CursorHold', l:events)
  call assert_match('BufEnter', l:events)
  call assert_match('FocusGained', l:events)
  call assert_notmatch('CursorHoldI', l:events)
  call assert_false(&autowrite)
  call assert_false(&autowriteall)
  call assert_true(&backup)
  call assert_true(&writebackup)
  call assert_true(&undofile)
endfunction


function! s:TestConvergedDraftAndAnchoredRefresh() abort
  let l:path = s:Open('converged.tex', ['original'])
  call setline(1, 'same revision')
  call writefile(['same revision'], l:path)
  call assert_true(OnesimusCheckExternalChanges(0))
  call assert_false(&modified)
  call assert_false(OnesimusHasExternalConflict())
  let l:path = s:Open('anchored.tex', ['start', 'reading here', 'end'])
  call cursor(2, 4)
  let l:first = win_getid()
  split
  call cursor(3, 2)
  let l:second = win_getid()
  call writefile(['new paragraph', 'start', 'reading here', 'end'], l:path)
  call assert_true(OnesimusCheckExternalChanges(0))
  call assert_equal(4, line('.'))
  call win_gotoid(l:first)
  call assert_equal(3, line('.'))
  call assert_equal('reading here', getline('.'))
  call win_gotoid(l:second)
  close
endfunction

function! s:TestHiddenMainAndSharedBibliography() abort
  let l:outside = fnamemodify(s:fixture, ':h').'/'.fnamemodify(s:fixture, ':t').'-shared.bib'
  try
    call writefile(['@book{shared,}'], l:outside)
    let l:main = s:Open('hidden main.tex', ['\documentclass{article}',
          \ '\addbibresource{'.l:outside.'}', '\input{child}'])
    let l:main_buf = bufnr('%')
    let l:state = b:vimtex
    call s:Open('hidden child.tex', ['body'])
    let b:vimtex = l:state
    let l:child_buf = bufnr('%')
    call writefile(['\documentclass{book}', '\addbibresource{'.l:outside.'}', '\input{child}'], l:main)
    call OnesimusCheckExternalChanges(1)
    call assert_false(OnesimusDiskChanged(l:main_buf))
    call assert_equal(l:child_buf, bufnr('%'))
    call assert_equal('\documentclass{book}', getbufline(l:main_buf, 1)[0])
    call assert_true(index(OnesimusTexProjectFiles(l:state), resolve(l:outside)) >= 0)
    execute 'edit '.fnameescape(l:outside)
    setfiletype bib
    call setline(1, '@book{local,}')
    execute 'buffer '.l:child_buf
    call setline(1, 'child draft')
    let g:onesimus_tex_compile_once_calls = 0
    call assert_false(OnesimusTexBuildOnce())
    call assert_true(&modified)
    call assert_equal(0, g:onesimus_tex_compile_once_calls)
  finally
    execute 'silent! bwipeout! '.fnameescape(l:outside)
    call delete(l:outside)
  endtry
endfunction

function! s:TestReviewedWriteAllowsPreWriteFormatter() abort
  let l:path = s:Open('formatted resolution.tex', ['base'])
  call setline(1, 'local')
  call writefile(['external'], l:path)
  call OnesimusCheckExternalChanges(0)
  let l:scratch = OnesimusDiffDisk()
  augroup onesimus_test_formatter
    autocmd!
    autocmd BufWritePre <buffer> call setline(1, 'formatted merge')
  augroup END
  try
    " Vim's native timestamp confirmation is separate from Onesimus's
    " reviewed revision check and remains present even for :write!.
    call assert_true(OnesimusCommitReviewedSource())
    call assert_equal(['formatted merge'], readfile(l:path))
    call assert_false(&modified)
  finally
    augroup onesimus_test_formatter
      autocmd!
    augroup END
    execute 'silent! bwipeout! '.l:scratch
    diffoff!
  endtry
endfunction

function! s:TestFailedRefreshBlocksBuild() abort
  let l:path = s:Open('refresh failure.tex', ['old disk'])
  call writefile(['external revision'], l:path)
  let g:onesimus_tex_compile_once_calls = 0
  augroup onesimus_test_failed_syntax
    autocmd!
    autocmd Syntax tex throw 'synthetic syntax refresh failure'
  augroup END
  try
    call assert_false(OnesimusTexBuildOnce())
    call assert_equal(0, g:onesimus_tex_compile_once_calls)
    call assert_equal(['external revision'], readfile(l:path))
  finally
    augroup onesimus_test_failed_syntax
      autocmd!
    augroup END
    call OnesimusCheckExternalChanges(0)
  endtry
endfunction

function! OnesimusRunTeXTests() abort
  try
    call s:TestF5SafeSaveThenBuild()
    call s:TestAlternateTeXExtensionKeepsBaseline()
    call s:TestUnavailableCompilerDoesNotSave()
    call s:TestMissingVimtexDoesNotSave()
    call s:TestUnavailableLiveModeDoesNotSave()
    call s:TestMissingWritingAndViewerToolsAreFriendly()
    call s:TestBrowserViewAndFeedbackNeverSave()
    call s:TestRevisionNeverSavesAnUnsavedDraft()
    call s:TestSentenceLinesStayUnsavedAndUndoable()
    call s:TestRealSentenceCommandUsesStdinAndOwnUndoBlock()
    call s:TestSentenceFailureAndConflictPreserveSource()
    call s:TestConflictBlocksSaveAndBuild()
    call s:TestF5LatePreWriteChangeBlocksSaveAndBuild()
    call s:TestLatePostWriteChangeBlocksSaveAndBuild()
    call s:TestNoFinalNewlineAndBomRoundTrip()
    call s:TestUseDiskKeepsBufferIdentity()
    call s:TestDiffDiskIgnoresFileReadHooks()
    call s:TestCleanExternalReload()
    call s:TestStructuralReloadRefreshesVimtexState()
    call s:TestLocalStructuralEditBuildsAfterReload()
    call s:TestSymlinkedSourceIsGuarded()
    call s:TestUnknownDirtyBaselineBlocksFirstWrite()
    call s:TestDiffDiskDecodesDosLines()
    call s:TestBangCannotBypassFingerprintGuard()
    call s:TestRangeWriteCannotBypassGuard()
    call s:TestWriteCopyAndSaveAsKeepPathIdentity()
    call s:TestAlternateExistingObjectCannotBeOverwritten()
    call s:TestDirtyProjectMemberBlocksWholeBuild()
    call s:TestBibConflictHasDiscoverableActions()
    call s:TestDeletedSourceIsPreserved()
    call s:TestUnreadableSourceCannotMasqueradeAsDeleted()
    call s:TestSyntheticPreservationReloadsWhenPathRecovers()
    call s:TestRepeatedDiffReusesCurrentDiskView()
    call s:TestFailedDiffDoesNotAuthorizeOverwrite()
    call s:TestReviewedRevisionChangingAtFinalGuardIsBlocked()
    call s:TestConvergedDraftAndAnchoredRefresh()
    call s:TestHiddenMainAndSharedBibliography()
    call s:TestReviewedWriteAllowsPreWriteFormatter()
    call s:TestFailedRefreshBlocksBuild()
    call s:TestEventAndStoragePolicy()
  finally
    call delete(s:fixture, 'rf')
  endtry
  call writefile(empty(v:errors) ? ['PASS'] : v:errors, '/tmp/onesimus-tex-workflow-result')
  if empty(v:errors)
    qall!
  endif
  for l:error in v:errors
    echomsg l:error
  endfor
  cquit
endfunction
