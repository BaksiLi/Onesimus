" ALE buffer-state ownership and teardown regression.
" Run with:
"   vim -Nu tests/ale_lifecycle.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

function! s:RunALELifecycleTests() abort
  new
  file /tmp/onesimus-ale-lifecycle.py
  " Keep the fixture deterministic when pylsp happens to be installed: the
  " test fires ALE's lifecycle event explicitly after installing its baseline.
  let b:ale_disable_lsp = 1
  setlocal filetype=python
  setlocal omnifunc=syntaxcomplete#Complete
  nnoremap <buffer> gd :let g:onesimus_original_gd = 1<CR>
  let l:original_gd = maparg('gd', 'n', 0, 1)
  call assert_false(exists('b:onesimus_lsp_omnifunc_before'),
        \ 'the disabled fixture has not received a real LSP event')
  call assert_equal('syntaxcomplete#Complete', &l:omnifunc)

  doautocmd <nomodeline> User ALELSPStarted
  call assert_equal(1, get(b:, 'onesimus_lsp_ready', 0))
  call assert_equal('ale#completion#OmniFunc', &l:omnifunc)
  call assert_match('OnesimusTrack.*ale_go_to_definition', maparg('gd', 'n'))
  call assert_match('OnesimusTrack.*ale_find_references', maparg('gr', 'n'))

  " A user decision made after startup is no longer owned by Onesimus.
  nnoremap <buffer> gr :let g:onesimus_user_gr = 1<CR>
  let l:user_gr = maparg('gr', 'n', 0, 1)
  setlocal filetype=text

  call assert_false(exists('b:onesimus_lsp_ready'))
  call assert_equal('', &l:omnifunc,
        \ 'the incoming ftplugin may replace omnifunc before our cleanup')
  call assert_equal(l:original_gd, maparg('gd', 'n', 0, 1),
        \ 'the prior buffer-local mapping is restored exactly')
  call assert_equal(l:user_gr, maparg('gr', 'n', 0, 1),
        \ 'a mapping changed during the lease belongs to the user')
  call assert_equal('', maparg('K', 'n'),
        \ 'teardown reveals Vim native behavior when no mapping preceded it')
  call assert_equal('', maparg('<leader>rn', 'n'))
  call assert_equal('', maparg('<leader>ca', 'n'))

  " Disabling LSP without another FileType event is observed on ALE's next
  " lint cycle and follows the same teardown path.
  unlet b:ale_disable_lsp
  setlocal filetype=python
  let l:python_omnifunc = &l:omnifunc
  doautocmd <nomodeline> User ALELSPStarted
  call assert_equal(1, get(b:, 'onesimus_lsp_ready', 0))
  let b:ale_disable_lsp = 1
  doautocmd <nomodeline> User ALELintPre
  call assert_false(exists('b:onesimus_lsp_ready'))
  call assert_equal(l:python_omnifunc, &l:omnifunc)
  call assert_equal(l:original_gd, maparg('gd', 'n', 0, 1))
  call assert_equal(l:user_gr, maparg('gr', 'n', 0, 1))

  call writefile(v:errors, '/tmp/onesimus-ale-lifecycle-errors')
  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_ale_lifecycle_test
  autocmd!
  autocmd VimEnter * call <SID>RunALELifecycleTests()
augroup END
