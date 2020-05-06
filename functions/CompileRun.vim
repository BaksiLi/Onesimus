" TODO: configurable
" TODO: a more elegant way to do this
"   - expand macros as a function (%, filetype)
" TODO: HTML, and check if has ghc? initialise?

func! s:CompileRun()
  " AsyncRun -save={0,1,2} -post
  " -mode={}

  " Save?
  " exec 'w'
  
  " Open terminal
  let g:compilerun_term = -1
  " if = 1, position

  " Auto open :copen
  let g:asyncrun_open = 8
  let g:asyncrun_bell = 1

  " Timer
  let g:compilerun_timer = 1
  if g:compilerun_timer
    let expr_timer = 'time '
  else
    let expr_time = ''
  endif

  " ------ Run part ------
  if &filetype ==? 'sh'
    call asyncrun#run('', {}, expr_timer.'bash '.expand('%'))
  elseif &filetype ==? 'python'
    call asyncrun#run('raw', {}, expr_timer.'python '.expand('%'))
  elseif &filetype ==? 'markdown'
    " exec '!~/.vim/markdown.pl % > %.html &'
    " exec '!open -a \"Google Chrome\" %.html &'  " only for macOS
    exec 'MarkdownPreview'
    echo 'Markdown Preview Toggled'
  elseif &filetype ==? 'tex'
    " vimtex compile key
    exec 'normal \ll'
  elseif &filetype ==? 'html'
    exec '!open -a "Google Chrome" % &'
  elseif &filetype ==? 'haskell'
    call asyncrun#run('', {}, expr_timer.'ghc '.expand('%'))
  elseif &filetype ==? 'vim'
    exec 'so %'
  elseif &filetype ==? 'dot'
    let command = 'dot -Tpng '.expand(%).' -o '.expand(%:r).'.png && open '.expand(%:r)'.png'
    call asyncrun#run('', {}, expr_timer.command)
    
  endif

  " ------ Compile part ------
  if &filetype ==? 'c'
    exec '!g++ % -o %<'
    " AsyncRun gcc -Wall -O2 '$(VIM_FILEPATH)' -o  '$(VIM_FILEDIR)/$(VIM_FILENOEXT)'
    exec '!time ./%<'
    " AsyncRun -raw -cwd=$(VIM_FILEDIR) '$(VIM_FILEDIR)/$(VIM_FILENOEXT)'
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

  " if filetype is not listed
  " echo 'CompileRun Error: Not a supported filetype!'
endfunc

command! CompileRun call <sid>CompileRun()

" Range support for assyncrun
