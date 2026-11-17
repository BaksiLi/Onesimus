" The core: Onesimus without third-party plugins, chosen by g:onesimus_core
" or by starting the binary as `vi`.

let s:repo = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let g:onesimus_core = 1
execute 'source '.fnameescape(s:repo.'/init.vim')

call assert_equal({}, get(g:, 'plugs', {}), 'the core declares no plugins')
call assert_false(exists('*plug#begin'), 'the core does not load vim-plug')
call assert_equal(2, exists(':One'))
call assert_true(index(getcompletion('One ', 'cmdline'), 'redraw') >= 0)
call assert_equal('%!OnesimusStatusline()', &statusline)

One manual
call assert_equal('help', &buftype)
call assert_match('/doc/onesimus.txt$', expand('%:p'), '\\? opens :help onesimus')
helpclose

let s:dir = tempname()
call mkdir(s:dir)
execute 'edit '.fnameescape(s:dir.'/paper.tex')
call assert_equal('tex', &filetype)
call assert_false(exists('g:onesimus_tex_module'), 'the TeX module needs VimTeX')
call assert_false(exists('b:vimtex'))

" `vi` is the same binary under another name.
let s:vi = s:dir.'/vi'
call system('ln -s '.shellescape(resolve(v:progpath)).' '.shellescape(s:vi))
let s:out = s:dir.'/core'
call system(shellescape(s:vi).' -Nu '.shellescape(s:repo.'/init.vim')
      \ .' -i NONE -n -es -c '.shellescape('call writefile([g:onesimus_core], "'.s:out.'")')
      \ .' -c qa! </dev/null')
call assert_equal(['1'], readfile(s:out), 'starting as vi chooses the core')

if empty(v:errors)
  qall!
endif
for s:error in v:errors
  echomsg s:error
endfor
cquit
