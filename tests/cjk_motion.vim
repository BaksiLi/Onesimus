" Optional jieba.vim integration test.
" Run with:
"   vim -Nu tests/cjk_motion.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

function! s:RunCJKMotionTests() abort
  call assert_false(exists('g:loaded_jieba_vim'),
        \ 'jieba stays unloaded until Han text is observed')

  " A filetype allow-list may narrow automatic loading without changing the
  " explicit :OnesimusJiebaEnable escape hatch.
  let g:onesimus_jieba_filetypes = ['markdown']
  enew
  call setline(1, '中文註解')
  setfiletype python
  call assert_false(exists('g:loaded_jieba_vim'),
        \ 'a disallowed filetype does not trigger jieba')

  enew
  call setline(1, repeat(['ASCII'], 300) + ['〇'])
  setfiletype markdown
  call assert_false(exists('g:loaded_jieba_vim'),
        \ 'the initial bounded scan stops after 300 lines')
  call cursor(301, 1)
  doautocmd CursorMoved
  call assert_true(exists('g:loaded_jieba_vim'),
        \ 'moving onto later Han text activates the lazy bridge')

  if !exists('*OnesimusJiebaReady') || !OnesimusJiebaReady()
    call writefile(['SKIP', 'jieba.vim backend is unavailable'],
          \ '/tmp/onesimus-cjk-motion-result')
    qall!
  endif

  call assert_equal('<Plug>(Jieba_w)', maparg('w', 'n'))

  call setline(1, '我来到北京清华大学')
  call cursor(1, 1)
  call feedkeys('w', 'xt')
  call assert_equal(4, col('.'), 'w moves from 我 to 来到')
  call feedkeys('w', 'xt')
  call assert_equal(10, col('.'), 'w moves from 来到 to 北京')

  call setline(1, 'alpha beta')
  call cursor(1, 1)
  call feedkeys('w', 'xt')
  call assert_equal(7, col('.'), 'ASCII w keeps native behavior')

  call setline(1, '我来到北京')
  call cursor(1, 4)
  call feedkeys('diw', 'xt')
  call assert_equal('我北京', getline(1), 'diw uses a segmented Chinese word')

  let g:onesimus_test_operator_calls = 0
  let l:operatorfunc = &operatorfunc
  function! OnesimusTestCJKOperator(type) abort
    let g:onesimus_test_operator_calls += 1
  endfunction
  let &operatorfunc = 'OnesimusTestCJKOperator'
  call setline(1, '我来到北京')
  call cursor(1, 4)
  call feedkeys('g@iw', 'xt')
  call assert_equal(1, g:onesimus_test_operator_calls,
        \ 'g@ reaches its operatorfunc through the native text object')
  let &operatorfunc = l:operatorfunc
  delfunction OnesimusTestCJKOperator
  unlet g:onesimus_test_operator_calls

  call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors,
        \ '/tmp/onesimus-cjk-motion-result')
  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_cjk_motion_test
  autocmd!
  autocmd VimEnter * call <SID>RunCJKMotionTests()
augroup END
