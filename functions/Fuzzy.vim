" A small action facade keeps mappings useful while vim-clap is optional.

let s:clap_providers = {
      \ 'buffers': 1,
      \ 'colors': 1,
      \ 'command_history': 1,
      \ 'files': 1,
      \ 'git_files': 1,
      \ 'grep': 1,
      \ 'history': 1,
      \ 'marks': 1,
      \ 'proj_tags': 1,
      \ 'tags': 1,
      \ }

function! s:OpenClap(provider) abort
  if !has_key(s:clap_providers, a:provider)
    echohl ErrorMsg
    echomsg 'Unknown Onesimus picker: '.a:provider
    echohl None
    return
  endif

  if PlugInstalled('vim-clap') && exists(':Clap')
    if exists('*OnesimusTrack')
      call OnesimusTrack('find.'.a:provider)
    endif
    execute 'Clap '.a:provider
    return
  endif

  echohl WarningMsg
  echomsg 'vim-clap is not installed; run :PlugInstall vim-clap.'
  echohl None
endfunction

command! -nargs=1 OnesimusClap call <SID>OpenClap(<q-args>)
