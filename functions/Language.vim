" Stable language actions.  Mappings call Onesimus commands rather than a
" plugin directly, so providers can change without changing muscle memory.

function! s:BufferSymbols() abort
  if PlugInstalled('vim-clap') && exists(':Clap')
    call OnesimusTrack('nav.buffer_symbols')
    Clap tags
    return
  endif

  echohl WarningMsg
  echomsg 'Buffer symbols need vim-clap; run :PlugInstall vim-clap.'
  echohl None
endfunction

function! s:ALEWorkspaceSymbolsAvailable() abort
  if !exists(':ALESymbolSearch')
    return 0
  endif

  try
    for l:linter in ale#lsp_linter#GetEnabled(bufnr(''))
      " ALE does not implement workspace-symbol requests through tsserver.
      if l:linter.lsp isnot# 'tsserver'
            \ && executable(ale#linter#GetExecutable(bufnr(''), l:linter))
        return 1
      endif
    endfor
  catch
    return 0
  endtry

  return 0
endfunction

function! s:ProjectTagsAvailable() abort
  if !PlugInstalled('vim-clap') || !exists(':Clap') || !executable('ctags')
    return 0
  endif

  let l:version = system('ctags --version')
  if v:shell_error || l:version !~# 'Universal Ctags'
    return 0
  endif

  let l:features = systemlist('ctags --list-features')
  return v:shell_error == 0 && index(l:features, 'json') >= 0
endfunction

function! OnesimusWorkspaceSymbolsAvailable() abort
  return s:ALEWorkspaceSymbolsAvailable() || s:ProjectTagsAvailable()
endfunction

function! s:WorkspaceSymbols() abort
  let l:query = input('Workspace symbol: ', expand('<cword>'))
  redraw

  if empty(l:query)
    return
  endif

  if s:ALEWorkspaceSymbolsAvailable()
    call OnesimusTrack('nav.workspace_symbols')
    execute 'ALESymbolSearch '.escape(l:query, ' |')
  elseif s:ProjectTagsAvailable()
    call OnesimusTrack('nav.workspace_symbols')
    execute 'Clap proj_tags --query='.fnameescape(l:query)
  elseif PlugInstalled('vim-clap') && exists(':Clap')
    echohl WarningMsg
    echomsg 'Project tags need Universal Ctags with +json support.'
    echohl None
  else
    echohl WarningMsg
    echomsg 'Workspace symbols need an ALE language server or vim-clap.'
    echohl None
  endif
endfunction

command! OnesimusBufferSymbols call <SID>BufferSymbols()
command! OnesimusWorkspaceSymbols call <SID>WorkspaceSymbols()

nnoremap <silent> gs :OnesimusBufferSymbols<CR>
nnoremap <silent> gS :OnesimusWorkspaceSymbols<CR>
