" Assert that init.vim discovers its own checkout without installer variables.

let s:repo = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
call assert_equal(s:repo, fnamemodify(resolve($VIMRCDIR), ':p:h'))
call assert_equal(s:repo.'/init.vim', resolve($MYVIMDOT))
call assert_equal(1, get(g:, 'onesimus_bootstrap_ready', 0))
call assert_equal(2, exists(':OnesimusGuide'))

if empty(v:errors)
  qall!
endif
for s:error in v:errors
  echomsg s:error
endfor
cquit
