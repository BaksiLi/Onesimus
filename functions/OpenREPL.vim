" A deliberately small REPL launcher.  It stays as an explicit, measurable
" legacy feature; there is no unfinished visual-range transport layer.

function! s:ExecutableForFiletype() abort
  if &filetype ==# 'python'
    return executable('python3') ? 'python3' : 'python'
  elseif &filetype ==# 'ruby'
    return 'irb'
  elseif &filetype ==# 'scheme'
    return executable('chez') ? 'chez' : 'scheme'
  elseif &filetype ==# 'haskell'
    return 'ghci'
  endif
  return ''
endfunction

function! s:OpenREPL() abort
  if &filetype ==# 'vim'
    call OnesimusTrack('repl.open')
    normal! gQ
    return
  endif

  let l:program = s:ExecutableForFiletype()
  if empty(l:program)
    echohl WarningMsg
    echomsg 'No Onesimus REPL is configured for '.(&filetype ==# ''
          \ ? 'this buffer' : &filetype).'.'
    echohl None
    return
  endif
  if !exists(':terminal') || !executable(l:program)
    echohl WarningMsg
    echomsg 'REPL needs Vim +terminal and executable: '.l:program
    echohl None
    return
  endif

  call OnesimusTrack('repl.open')
  execute 'terminal '.l:program
endfunction

command! OpenREPL call <SID>OpenREPL()
