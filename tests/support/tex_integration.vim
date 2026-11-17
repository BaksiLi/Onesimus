" Run after VimEnter, using actual VimTeX and latexmk transports.
let s:fixture = resolve($ONESIMUS_TEST_PROJECT)
let g:vimtex_cache_root = s:fixture.'/cache'
let g:vimtex_compiler_silent = 1
let g:vimtex_view_automatic = 0
" A personal custom/settings.vim may name a relay host.
let g:webpreview_host = '127.0.0.1'
let s:opened = []
function! OnesimusOpenBrowser(url) abort
  call add(s:opened, a:url)
  return 1
endfunction
let s:document = ['\documentclass{article}', '\begin{document}', 'A paper.', '\end{document}']

function! s:Open(name, lines) abort
  let l:directory = s:fixture.'/'.a:name
  call mkdir(l:directory, 'p')
  let l:path = l:directory.'/main.tex'
  call writefile(a:lines, l:path)
  execute 'edit '.fnameescape(l:path)
  return b:vimtex
endfunction

function! s:Wait(state) abort
  for l:i in range(1500)
    if !a:state.compiler.is_running() && index([2, 3], a:state.compiler.status) >= 0
      return
    endif
    sleep 20m
  endfor
  call assert_report('build timed out: '.a:state.tex)
  call a:state.compiler.stop()
endfunction

function! s:WaitRevision(state, expected) abort
  for l:i in range(1000)
    if get(get(a:state.compiler, 'onesimus_pdf_revision', {}), a:state.tex, '') ==# a:expected
          \ && a:state.compiler.status == 2
      return
    endif
    sleep 20m
  endfor
  call assert_report('live build did not publish the expected source revision')
endfunction

function! OnesimusTestVisualCheck() abort
  let g:visual_check_mode = mode(1)
  call writefile(['visual-time external revision'], expand('%:p'))
  call OnesimusCheckExternalChanges(0)
  let g:visual_check_text = getline(1)
endfunction

function! OnesimusTestInsertCheck() abort
  let g:insert_check_mode = mode(1)
  call writefile(['insert-time external revision'], expand('%:p'))
  call OnesimusCheckExternalChanges(0)
  let g:insert_check_text = getline(1)
  return ''
endfunction

try
  " Recurring timer, no movement or focus change, then a second idle edit.
  let s:refresh = s:Open('refresh', s:document)
  call writefile(['first external revision'] + s:document[1:], s:refresh.tex)
  sleep 220m
  call assert_equal('first external revision', getline(1), 'idle timer reloads')
  call writefile(['second external revision'] + s:document[1:], s:refresh.tex)
  sleep 220m
  call assert_equal('second external revision', getline(1), 'timer continues while idle')
  xnoremap <F12> <Cmd>call OnesimusTestVisualCheck()<CR>
  call feedkeys("v\<F12>\<Esc>", 'xt')
  xunmap <F12>
  call assert_equal('v', g:visual_check_mode)
  call assert_equal('second external revision', g:visual_check_text, 'selection is not replaced')
  call OnesimusCheckExternalChanges(0)
  call assert_equal('visual-time external revision', getline(1))
  call feedkeys("i\<C-r>=OnesimusTestInsertCheck()\<CR>\<Esc>", 'xt')
  call assert_match('^i', g:insert_check_mode)
  call assert_equal('visual-time external revision', g:insert_check_text, 'insert is not replaced')
  call OnesimusCheckExternalChanges(0)
  call assert_equal('insert-time external revision', getline(1))

  " Start A (failure) and B (success), then receive both while B is current.
  let s:a = s:Open('failed paper', s:document[:1] + ['\undefinedOnesimusCommand'] + s:document[3:])
  call assert_true(OnesimusTexBuildOnce())
  let s:b = s:Open('successful paper', s:document)
  call assert_true(OnesimusTexBuildOnce())
  call s:Wait(s:a)
  call s:Wait(s:b)
  call assert_equal(3, s:a.compiler.status, 'failure belongs to A')
  call assert_equal(2, s:b.compiler.status, 'success belongs to B')
  call assert_true(filereadable(s:b.compiler.get_file('pdf')))
  call assert_false(get(s:b.compiler, 'onesimus_pdf_stale', 1), 'first success is current')
  call assert_match('undefinedOnesimusCommand', join(readfile(s:a.compiler.output), "\n"))
  call assert_notmatch('undefinedOnesimusCommand', join(readfile(s:b.compiler.output), "\n"))

  " Change a known input after success; the PDF needs rebuilding.
  call writefile(s:document[:1] + ['Revised paper.'] + s:document[3:], s:b.tex)
  call OnesimusTexRefreshBuildStates()
  call assert_true(s:b.compiler.onesimus_pdf_stale)
  call OnesimusCheckExternalChanges(0)
  call assert_true(OnesimusTexToggleLiveBuild())
  let s:expected = sha256(join(readfile(s:b.tex, 'b'), "\n"))
  call s:WaitRevision(s:b, s:expected)
  call assert_false(s:b.compiler.onesimus_pdf_stale)
  call assert_true(OnesimusTexBuildAndView())
  for s:attempt in range(100)
    if !empty(s:opened) | break | endif
    sleep 20m
  endfor
  call assert_equal(1, len(s:opened), 'F5 opens an already-current live PDF in the browser')
  call assert_match('http://127\.0\.0\.1:', s:opened[0])

  " The next live cycle finishes while an unrelated project is current.
  let s:c = s:Open('unrelated paper', s:document)
  let s:untouched = s:c.compiler.status
  call writefile(s:document[:1] + ['Second live revision.'] + s:document[3:], s:b.tex)
  let s:expected = sha256(join(readfile(s:b.tex, 'b'), "\n"))
  call s:WaitRevision(s:b, s:expected)
  call assert_equal(s:untouched, s:c.compiler.status)
  call s:b.compiler.stop()
  call assert_false(s:b.compiler.is_running())

  " Cancellation suppresses a late completion from the stopped generation.
  let s:slow = s:fixture.'/slow-latexmk'
  call writefile(['#!/bin/sh', 'sleep 1', 'exec latexmk "$@"'], s:slow)
  let s:c.compiler.executable = 'sh '.shellescape(s:slow)
  call assert_true(OnesimusTexBuildOnce())
  call s:c.compiler.stop()
  sleep 1200m
  call assert_equal(0, s:c.compiler.status, 'cancelled job cannot report success')
  call assert_true(OnesimusTexBuildOnce())
  call writefile(s:document[:1] + ['Changed while building.'] + s:document[3:], s:c.tex)
  call s:Wait(s:c)
  call assert_equal(2, s:c.compiler.status)
  call assert_true(s:c.compiler.onesimus_pdf_stale, 'concurrent change is not certified current')
  call OnesimusTexRefreshBuildStates()
  call assert_true(s:c.compiler.onesimus_pdf_stale, 'timer cannot erase a known build race')

  " Check the real VimTeX syntax context used by Python snippet expressions.
  call setline(3, 'Prose x2 and $x2$ in math.')
  syntax sync fromstart
  call cursor(3, 8)
  call assert_equal(0, vimtex#syntax#in_mathzone())
  call cursor(3, 16)
  call assert_equal(1, vimtex#syntax#in_mathzone(), string(map(synstack(3, 16), 'synIDattr(v:val, "name")')))
  if has('python3') && exists(':UltiSnipsEdit') == 2
    call cursor(3, 1)
    call feedkeys("cc$x2\<C-e>\<Esc>", 'xt')
    call assert_equal('$x_2', getline(3), 'actual math snippet expands')
    call feedkeys("ccProse x2\<Esc>", 'xt')
    call assert_equal('Prose x2', getline(3), 'prose is not rewritten by a math snippet')
  endif
catch
  call assert_report(v:exception.' at '.v:throwpoint)
finally
  for s:state in vimtex#state#list_all()
    if has_key(s:state, 'compiler') && s:state.compiler.is_running()
      call s:state.compiler.stop()
    endif
  endfor
endtry
if !empty(v:errors)
  for s:error in v:errors
    echomsg s:error
  endfor
  cquit
endif
call writefile(['PASS'], s:fixture.'/passed')
qall!
