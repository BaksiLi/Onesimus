" Browser-selected text must match actual source before entering Visual.
set nocompatible
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^='.fnameescape(s:root)
let s:plugins = empty($ONESIMUS_PLUGIN_HOME) ? expand('~/.vim/bundle') : $ONESIMUS_PLUGIN_HOME
execute 'set runtimepath^='.fnameescape(s:plugins.'/webpreview.vim')
execute 'source '.fnameescape(s:root.'/functions/Writing.vim')
function! s:Select(lines, text, anchor, expected) abort
  enew!
  call setline(1, a:lines)
  setlocal foldmethod=manual
  if len(a:lines) > 1
    execute '1,'.len(a:lines).'fold'
    normal! zM
  endif
  call cursor(1, 1)
  let l:tick = b:changedtick
  let l:disk = getline(1, '$')
  call assert_true(OnesimusWritingSelect(a:text, a:anchor), a:text)
  call assert_equal('v', mode(1))
  call assert_equal(-1, foldclosed(line('.')), 'selection unfolds its endpoint')
  normal! y
  call assert_equal(a:expected, getreg('"'), a:text.' ['.&selection.']')
  call assert_equal(l:tick, b:changedtick)
  call assert_equal(l:disk, getline(1, '$'))
endfunction
function! s:Run() abort
  for l:selection in ['inclusive', 'exclusive']
    let &selection = l:selection
    call s:Select(['Prefix nine is composite. Suffix'], 'nine is composite.', 1, 'nine is composite.')
    call s:Select(['First line with', 'several words.', '', 'Elsewhere.'], 'with several words.', 2, "with\nseveral words.")
    call s:Select(['九不是素數。😀 下一句。'], '不是素數。😀', 1, '不是素數。😀')
    call s:Select(['A $x^2$ + [literal].'], '$x^2$ + [literal].', 1, '$x^2$ + [literal].')
    call s:Select(['one two'], 'two', 1, 'two')
  endfor
  enew!
  call setline(1, ['repeat repeat', '', 'Unique outside paragraph'])
  call assert_false(OnesimusWritingSelect('repeat', 1))
  call assert_false(OnesimusWritingSelect('outside', 1))
  call assert_false(OnesimusWritingSelect('rendered formula', 1))
  call assert_false(OnesimusWritingSelect(' ', 1))
  call setline(1, 'a a a')
  call assert_false(OnesimusWritingSelect('a a', 1), 'overlapping matches are ambiguous')
  set ignorecase
  call setline(1, 'Case case')
  call assert_true(OnesimusWritingSelect('Case', 1), 'literal matching is case-sensitive')
  normal! y
  call assert_equal('Case', getreg('"'))
  if !empty(v:errors)
    call writefile(v:errors, '/tmp/onesimus-writing-selection-errors')
    cquit
  endif
  qall!
endfunction
autocmd VimEnter * call <SID>Run()
