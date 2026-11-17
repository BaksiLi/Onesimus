" Run in normal screen mode: vim -Nu tests/writing_display.vim -i NONE -n
" Ex mode does not initialize the screen and cannot verify visual wrapping.
let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)
" These tests exercise layout/fixing, not asynchronous language servers.
let g:ale_linters = {}

function! s:Run() abort
  try
    set nomore
    set lines=30 columns=60 laststatus=0 scrolloff=0
    enew
    call setline(1, [
          \ 'Dr. Li measured 3.14 units; this clause belongs together, despite its comma.',
          \ '中文沒有空格。這是第二句；也有 English words，以及中文標點。',
          \ '- A list item with several words that continue across more than one screen row.',
          \ ])
    setfiletype markdown
    setlocal nonumber norelativenumber signcolumn=no foldcolumn=0 nolist
    let l:source = getline(1, '$')
    let l:tick = b:changedtick
    let l:modified = &l:modified
    for l:width in [30, 45]
      vertical split
      execute 'vertical resize '.l:width
      redraw!
      let l:start = screenpos(win_getid(), 1, 1)
      let l:word = screenpos(win_getid(), 1, match(getline(1), 'measured') + 1)
      let l:end = screenpos(win_getid(), 1, strlen(getline(1)))
      call assert_true(l:start.row > 0 && l:end.row > l:start.row,
            \ 'one physical line occupies several real display rows')
      call assert_equal(l:word.row,
            \ screenpos(win_getid(), 1, match(getline(1), 'measured') + 8).row,
            \ 'an English word that fits is kept together')
      call assert_equal('↳', screenstring(l:start.row + 1, l:start.col),
            \ 'soft rows have a visible continuation marker')
      let l:cjk = screenpos(win_getid(), 2, 1)
      call assert_true(screenpos(win_getid(), 2, strlen(getline(2)) - 2).row > l:cjk.row,
            \ 'mixed CJK and English also soft-wrap')
      let l:list = screenpos(win_getid(), 3, 1)
      call assert_equal('↳', screenstring(l:list.row + 1, l:list.col + 2),
            \ 'wrapped list text retains its hanging indent')
      call cursor(1, 1)
      call feedkeys("\<Down>", 'xt')
      call assert_equal(1, line('.'), 'Normal arrows stay within a wrapped source line')
      call assert_equal(l:start.row + 1,
            \ screenpos(win_getid(), line('.'), col('.')).row)
      call cursor(1, 1)
      call feedkeys("i\<Down>\<Cmd>let g:onesimus_arrow_row = screenpos(win_getid(), line('.'), col('.')).row\<CR>\<Esc>", 'xt')
      call assert_equal(l:start.row + 1, g:onesimus_arrow_row,
            \ 'Insert arrows follow the displayed row on touch terminals')
      call cursor(1, 1)
      call feedkeys("v\<Down>\<Cmd>let g:onesimus_arrow_row = screenpos(win_getid(), line('.'), col('.')).row\<CR>\<Esc>", 'xt')
      call assert_equal(l:start.row + 1, g:onesimus_arrow_row,
            \ 'Visual selection extends by displayed rows')
      call assert_equal(l:source, getline(1, '$'))
      call assert_equal(l:tick, b:changedtick)
      call assert_equal(l:modified, &l:modified)
      close
    endfor

    " A word that just fits must take its punctuation with it when wrapping.
    enew!
    setfiletype text
    setlocal nonumber norelativenumber signcolumn=no foldcolumn=0 nolist
    for l:width in [30, 45]
      execute 'set columns='.l:width
      for l:punctuation in ['.', ',', ';', ':', '!', '?']
        let l:word = repeat('w', l:width - 7)
        call setline(1, 'prefix '.l:word.l:punctuation)
        redraw!
        call assert_equal(screenpos(win_getid(), 1, 8).row,
              \ screenpos(win_getid(), 1, strlen(getline(1))).row,
              \ 'punctuation stays with the word at width '.l:width)
      endfor
    endfor
    set columns=60

    enew!
    call setline(1, [
          \ '$k_g(\omega)=\omega/v_g$',
          \ '$\alpha + x^2 + x_g$',
          \ '$\frac{\omega}{v_{g}} + \custom{x^2}$',
          \ 'after',
          \ ])
    setfiletype tex
    setlocal nonumber norelativenumber signcolumn=no foldcolumn=0 nolist
    setlocal foldmethod=manual foldenable
    2,3fold
    call feedkeys('gg3G', 'xt')
    call assert_equal(3, line('.'))
    call assert_equal(-1, foldclosed('.'), 'a counted line jump reveals its target')
    normal! zc
    normal! gg
    normal! j
    call assert_equal(2, foldclosed('.'), 'ordinary movement keeps deliberately closed folds')
    setlocal filetype=python
    for l:mode in ['n', 'i', 'x']
      call assert_false(get(maparg('<Down>', l:mode, 0, 1), 'buffer', 0),
            \ 'prose arrow mappings leave with the filetype')
    endfor
  catch
    call add(v:errors, v:exception.' at '.v:throwpoint)
  endtry
  call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors,
        \ '/tmp/onesimus-writing-display-result')
  if !empty(v:errors)
    cquit
  endif
  qall!
endfunction
augroup onesimus_writing_display_test
  autocmd!
  autocmd VimEnter * ++nested call <SID>Run()
augroup END
