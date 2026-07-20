" A missing jieba backend must leave Vim's core word motions untouched.
" Run with:
"   vim -Nu tests/cjk_fallback.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')

" Simulate mappings left by an unavailable/broken backend.
nmap w <Plug>(Jieba_w)
xmap iw <Plug>(Jieba_iw)
omap iw <Plug>(Jieba_iw)
let g:jieba_vim_keymap = 1
execute 'source '.fnameescape($VIMRCDIR.'/plugconf/CJK.vim')

function! s:RunFallbackTests() abort
  call assert_false(OnesimusJiebaReady())
  call assert_equal(0, g:jieba_vim_keymap)
  call assert_equal('', maparg('w', 'n'))
  call assert_equal('', maparg('iw', 'x'))
  call assert_equal('', maparg('iw', 'o'))

  enew
  call setline(1, 'alpha beta')
  normal! gg0w
  call assert_equal(7, col('.'), 'native w remains available')

  call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors,
        \ '/tmp/onesimus-cjk-fallback-result')
  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_cjk_fallback_test
  autocmd!
  autocmd VimEnter * call <SID>RunFallbackTests()
augroup END
