" VimTeX compiles; Onesimus owns previews on every platform.
set nocompatible
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
for s:platform in ['darwin', 'linux', 'windows']
  let g:asc_uname = s:platform
  let g:vimtex_view_enabled = 1
  let g:vimtex_view_automatic = 1
  execute 'source '.fnameescape(s:root.'/plugconf/Languages.vim')
  execute 'source '.fnameescape(s:root.'/plugconf/Languages.vim')
  call assert_equal(0, g:vimtex_view_enabled)
  call assert_equal(0, g:vimtex_view_automatic)
  call assert_false(exists('g:vimtex_view_general_viewer'))
endfor
if !empty(v:errors)
  for s:error in v:errors | echomsg s:error | endfor
  cquit
endif
qall!
