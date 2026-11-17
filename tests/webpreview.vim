let s:repo = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'source '.fnameescape(s:repo.'/packages/webpreview.vim/tests/vim.vim')
