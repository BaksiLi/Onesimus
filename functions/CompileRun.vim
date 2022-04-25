" TODO: 
"  - expand macros as a function (%, filetype)
"  - HTML, and check if has ghc? initialise?
"  - detect io and switch to normal run mode.

func! s:CompileRun()
  " AsyncRun -save={0,1,2} -post
  " -mode={}

  " Retrieve file data
  " let header = getline(1) | let pos = stridx(header, '#!')
  let fname = expand('%')
  let frname = expand('%:r')
  let fpath = expand('%:p')

  " macOS absolute path has whitespaces
  if g:asc_uname ==? 'darwin'
    let fpath = substitute(fpath, '\ ', '\\ ', '')
  endif

  " Open terminal
  let g:compilerun_term = -1
  " if = 1, position

  " Auto open :copen
  let g:asyncrun_open = 8
  let g:asyncrun_bell = 1

  " Timer
  let g:compilerun_timer = 1
  if g:compilerun_timer
    let expr_timer = ''
  else
    let expr_time = ''
  endif

  exec 'update'

  " ------ Run part ------
  if &filetype ==? 'sh'
    call asyncrun#run('', {}, expr_timer.'bash '.fpath)
  elseif &filetype ==? 'python'
    call asyncrun#run('raw', {}, expr_timer.'python '.fpath)
  elseif &filetype ==? 'ruby'
    call asyncrun#run('raw', {}, expr_timer.'ruby '.fpath)
  elseif &filetype ==? 'markdown'
    " exec '!~/.vim/markdown.pl % > %.html &'
    " exec '!open -a \"Google Chrome\" %.html &'  " only for macOS
    exec 'MarkdownPreview'
    echo 'Markdown Preview Toggled'
  elseif &filetype ==? 'tex'
    " vimtex compile key
    exec 'VimtexCompile'
  elseif &filetype ==? 'html'
    exec '!open -a "Google Chrome" % &'
  elseif &filetype ==? 'haskell'
    call asyncrun#run('', {}, expr_timer.'ghc '.fpath)
  elseif &filetype ==? 'vim'
    exec 'so %'
  elseif &filetype ==? 'dot'
    let imgname = frname.'.png'
    let command = 'dot -Tpng '.fpath.' -o '.imgname.' && open '.imgname
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
