" Exercise source/display boundaries with real filetype and EditorConfig setup.
let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)
" These tests exercise layout/fixing, not asynchronous language servers.
let g:ale_linters = {}

function! s:Run() abort
  let l:dir = tempname()
  call mkdir(l:dir, 'p')
  let l:prose = [
        \ 'Dr. Li measured 3.14 units; this clause belongs together, despite its comma.',
        \ '中文沒有空格。這是第二句；也有 English words，以及中文標點。',
        \ '',
        \ '- A list with [a link](https://example.org/a.b?q=3.14) and `inline code`.',
        \ '  A continuation with a hard break.  ',
        \ '  Next displayed line.',
        \ '',
        \ '```text', '  literal content with trailing spaces  ', '```',
        \ '', '\emph{Words with punctuation.} More words $x=3.14$ and \cite{key}.',
        \ '% Comments remain on their own line; nothing after this becomes prose.',
        \ '\begin{verbatim}', '  literal TeX content  ', '\end{verbatim}',
        \ ]
  call writefile(['root = true', '[*]', 'indent_size = 5',
        \ 'max_line_length = 24', 'trim_trailing_whitespace = false'],
        \ l:dir.'/.editorconfig')
  try
    for [l:ext, l:ft] in [['md', 'markdown'], ['tex', 'tex'], ['txt', 'text'],
          \ ['cog.md', 'cogitatum']]
      let l:path = l:dir.'/draft.'.l:ext
      call writefile(l:prose, l:path)
      execute 'edit '.fnameescape(l:path)
      execute 'setlocal filetype='.l:ft
      let l:tick = b:changedtick
      let l:modified = &l:modified
      setlocal wrapmargin=12 formatoptions+=tca
      EditorConfigReload
      call assert_equal(5, &l:shiftwidth, 'unrelated EditorConfig rules survive')
      call assert_equal(0, &l:textwidth)
      call assert_equal(0, &l:wrapmargin)
      call assert_notmatch('[tca]', &l:formatoptions,
            \ 'text and comments never auto-reflow after EditorConfig reload')
      call assert_equal(l:prose, getline(1, '$'))
      call assert_equal(l:tick, b:changedtick)
      call assert_equal(l:modified, &l:modified)

      call cursor(1, strlen(getline(1)))
      execute "normal! A More words, still on this source line.\<Esc>"
      call assert_equal(len(l:prose), line('$'), 'ordinary input adds no EOL')
      let l:expected = copy(l:prose)
      let l:expected[0] .= ' More words, still on this source line.'
      call cursor(13, strlen(getline(13)))
      execute "normal! A More comment text beyond the configured width.\<Esc>"
      let l:expected[12] .= ' More comment text beyond the configured width.'
      call assert_equal(l:expected, getline(1, '$'),
            \ 'comments never auto-wrap; syntax-sensitive regions stay intact')
      silent write
      call assert_equal(l:expected, readfile(l:path), 'save does not reflow')
      bwipeout!
    endfor

    " A code buffer still obeys the project's width policy.
    call writefile(['print(1)'], l:dir.'/code.py')
    execute 'edit '.fnameescape(l:dir.'/code.py')
    EditorConfigReload
    call assert_equal(24, &l:textwidth)
    bwipeout!

    " Identity formatter isolates the ALE pipeline from external tool policy.
    " The previous generic cleanup destroyed hard breaks and verbatim spaces.
    let l:formatter = l:dir.'/formatter'
    call writefile(['#!/bin/sh', 'if [ "$1" = --version ]; then',
          \ '  echo 3.6.2', 'else', '  cat', 'fi'], l:formatter)
    call setfperm(l:formatter, 'rwx------')
    for [l:ext, l:ft] in [['md', 'markdown'], ['tex', 'tex']]
      let l:path = l:dir.'/format.'.l:ext
      call writefile(l:prose, l:path)
      execute 'edit '.fnameescape(l:path)
      execute 'setlocal filetype='.l:ft
      let b:ale_javascript_prettier_executable = l:formatter
      let b:ale_javascript_prettier_use_global = 1
      let b:ale_tex_latexindent_executable = l:formatter
      let l:input = copy(l:prose)
      let l:input[0] .= ' Unsaved revision.'
      call setline(1, l:input[0])
      let g:onesimus_layout_fix_done = 0
      augroup onesimus_layout_fix
        autocmd!
        autocmd User ALEFixPost let g:onesimus_layout_fix_done = 1
      augroup END
      call feedkeys("\<F6>", 'xt')
      let l:wait = 0
      while !g:onesimus_layout_fix_done && l:wait < 200
        sleep 10m
        let l:wait += 1
      endwhile
      call assert_true(g:onesimus_layout_fix_done, 'F6 reaches ALE and completes')
      call assert_equal(l:input, getline(1, '$'), 'no markup-blind cleanup')
      call assert_true(&l:modified, 'formatting leaves the revision unsaved')
      call assert_equal(l:prose, readfile(l:path), 'F6 never writes the file')
      bwipeout!
    endfor
  catch
    call add(v:errors, v:exception.' at '.v:throwpoint)
  finally
    call delete(l:dir, 'rf')
  endtry
  call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors,
        \ '/tmp/onesimus-writing-layout-result')
  if !empty(v:errors)
    cquit
  endif
  qall!
endfunction
augroup onesimus_writing_layout_test
  autocmd!
  autocmd VimEnter * ++nested call <SID>Run()
augroup END
