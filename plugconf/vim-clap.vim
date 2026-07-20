" vim-clap configuration
" Stay close to upstream defaults so every built-in provider remains usable.
let g:clap_popup_border = 'rounded'
let g:clap_enable_icon = get(g:, 'clap_enable_icon',
      \ exists('g:loaded_webdevicons') || get(g:, 'spacevim_nerd_fonts', 0))
let g:clap_popup_input_delay = 120

" Provider aliases for common commands
let g:clap_provider_alias = {
      \ 'gfiles': 'git_files',
      \ 'hist:': 'command_history',
      \ 'hist/': 'search_history',
      \ }
