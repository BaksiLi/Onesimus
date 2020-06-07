" ------ vim-markdown ------
let g:vim_markdown_math = 1
let g:vim_markdown_json_frontmatter = 1
let g:vim_markdown_strikethrough = 1

let g:markdown_enable_conceal = 0
let g:vim_markdown_new_list_item_indent = 2
let g:vim_markdown_follow_anchor = 1
let g:vim_markdown_folding_disabled = 1

let g:markdown_enable_mappings = 0
" This is evil. Should write a localleader version separately
" <space>
" inoremap <buffer> <localleader>e <Esc>:MarkdownEditBlock<CR>
" inoremap <silent> <buffer> <Leader>ft  <Esc>:call markdown#FormatTable()<CR>a

" ------ vim-markdown-folding ------
autocmd FileType markdown set foldexpr=NestedMarkdownFolds()

" ------ markdown-preview ------
let g:mkdp_browser = 'Google Chrome'
let g:mkdp_page_title = '${name}_preview'
" PlantUML, and others

" ------ vim-markdown-toc ------
