" TODO: Run asynchronously (skywind3000/asyncrun.vim)
" TODO: Make a configuration panel which remembers configuration of which
" compiler to use and so on. This should be compatible with OpenREPL(). Cf
" CocList()

func! s:CompileRun()
    exec 'w'
  if &filetype ==? 'c'
    exec '!g++ % -o %<'
    exec '!time ./%<'
  elseif &filetype ==? 'sh'
    exec '!time bash %'
  elseif &filetype ==? 'python'
    exec '!time python3 %'
  elseif &filetype ==? 'markdown'
    " exec '!~/.vim/markdown.pl % > %.html &'
    " exec '!open -a "Google Chrome" %.html &'  " only for macOS
    " MarkdownPreviewToggle
    exec 'MarkdownPreview'
    echo 'Markdown Preview Toggled'
  elseif &filetype ==? 'tex'
    " vimtex compile key
    exec 'normal \ll'
  elseif &filetype ==? 'html'
    exec '!open -a "Google Chrome" % &'
  elseif &filetype ==? 'haskell'
    exec '!time ghc %'
  elseif &filetype ==? 'vim'
    exec 'so %'
  elseif &filetype ==? 'dot'
    exec '!time dot -Tpng % -o %:r.png'.' && open %:r.png'
    " if macOS

  " ------ ------
  elseif &filetype ==? 'cpp'
    exec '!g++ % -o %<'
    exec '!time ./%<'
  elseif &filetype ==? 'java'
    exec '!javac %'
    exec '!time java %<'
  elseif &filetype ==? 'go'
    exec '!go build %<'
    exec '!time go run %'
  endif
endfunc

command! CompileRun call <sid>CompileRun()
