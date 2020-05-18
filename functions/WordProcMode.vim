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

func s:Global_set_of(arg)
	return split(execute('setg '.a:arg.'?'))[0]
endfun


func! s:WordProcessingMode()
  " Enable
  if !g:WPModeSwitch
		if PlugLoaded('vim-signify')
			SignifyDisable
		endif

    if PlugLoaded('Goyo') && PlugLoaded('Limelight')
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
		if PlugLoaded('vim-signify')
			SignifyEnable
		endif

    if PlugLoaded('Goyo') && PlugLoaded('Limelight')
      Goyo! | Limelight!
    else
      exec 'setlocal '.s:Global_set_of('nu')
      exec 'setlocal '.s:Global_set_of('textwidth')
		endif

		let g:WPModeSwitch = 0
		echo 'WordProcessingMode Off'
  endif

  setlocal smartindent
  setlocal noexpandtab

  "setlocal spell spelllang=en_uk,en_us
	
  "inoremap <C-l> <c-g>u<Esc>[s1z=`]a<c-g>u

  " Smart word count
  "   -> excl title, code
  "   -> excl specific section
endfu

command! WPModeToggle call <sid>WordProcessingMode()
