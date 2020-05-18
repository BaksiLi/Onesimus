" WordProcMode.vim
"		:- Focused writing experience, part of Onesimos Project
"
" Author: Baksi Li <myself@baksili.codes>
"
" License: MIT
"
" TODO: 
" 	- CJK wrap using google/budou (maybe worth a plugin, 'CJKwrap.vim'?)
" 	- Better implementation of restoring the global (prev) settings
" 	- https://github.com/amix/vim-zenroom2/blob/master/plugin/zenroom2.vim

func s:Global_set_of(arg)
  return split(execute('setg '.a:arg.'?'))[0]
endfun

func! s:PlugInstalled(plugname)
  return &runtimepath =~? a:plugname
endfun

let g:WPModeSwitch = 0

function! s:WordProcessingMode()
  " Enable
  if !g:WPModeSwitch
    if s:PlugInstalled('vim-signify')
      SignifyDisable
    endif

    if s:PlugInstalled('goyo') && s:PlugInstalled('limelight')
      Goyo | Limelight
    else
      setlocal nonumber
      setlocal textwidth=80
      silent on
    endif

    let g:WPModeSwitch = 1
    echo 'WordProcessingMode On'

    " Disable
  else
    if s:PlugInstalled('vim-signify')
      SignifyEnable
    endif

    if s:PlugInstalled('Goyo') && s:PlugInstalled('Limelight')
      Goyo! | Limelight!
    else
      exec 'setlocal '.s:Global_set_of('nu')
      exec 'setlocal '.s:Global_set_of('textwidth')
    endif

    let g:WPModeSwitch = 0
    echo 'WordProcessingMode Off'
  endif

  " set linespace=0
  " setlocal smartindent
  " setlocal noexpandtab

  "setlocal spell spelllang=en_uk,en_us

  "inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u

  " Smart word count
  "   -> excl title, code
  "   -> excl specific section
endfunction

command! WPModeToggle call <sid>WordProcessingMode()
