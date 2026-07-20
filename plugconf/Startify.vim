" Onesimus Home: compact, dynamic, and useful on a 24-line terminal.
"
" Startify still owns the well-tested MRU and empty-buffer edge cases.  We
" disable its direct VimEnter handler so Onesimus can open it silently after
" first-run plugin installation and avoid a misleading empty-viminfo warning.
let g:onesimus_home_enabled = get(g:, 'onesimus_home_enabled',
      \ !get(g:, 'startify_disable_at_vimenter', 0))
let g:startify_disable_at_vimenter = 1

let g:startify_lists = [
      \ {
      \   'type': { -> OnesimusHomeActions() },
      \   'header': ['  Quick actions'],
      \   'indices': ['f', '/', '?', 'i', 'u'],
      \ },
      \ {'type': 'files', 'header': ['  Recent files']},
      \ ]

let g:startify_files_number = &lines < 32 ? 3 : 6
let g:startify_update_oldfiles = 1
let g:startify_relative_path = 1
let g:startify_enable_special = 0

" Onesimus keeps one project CWD; Startify must not silently replace it.
let g:startify_change_to_dir = 0

" String expressions are evaluated only while rendering.  This stays safe on
" the very first run, before vim-startify has been installed.
let g:startify_custom_header = 'startify#pad(OnesimusHomeHeader())'
let g:startify_custom_footer = 'startify#pad(OnesimusHomeFooter())'
