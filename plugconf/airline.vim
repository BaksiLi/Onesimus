" Avoid probing dozens of integrations which Onesimus does not declare.
let g:airline_extensions = [
      \ 'ale', 'branch', 'fugitiveline', 'hunks', 'quickfix',
      \ 'tabline', 'term', 'vimtex', 'wordcount',
      \ ]

let g:airline_skip_empty_sections = 1
let g:airline_section_c = "%f %{&readonly ? '[RO] ' : ''} %{exists('*FindSubName') ? FindSubName() : ''}"
let g:airline#extensions#tabline#buffer_idx_mode = 1  " show buffer numbers
let g:airline#extensions#tabline#enabled = 1  " Automatically displays all buffers when there's only one tab open.

let g:airline_powerline_fonts = get(g:, 'airline_powerline_fonts', 0)

if PlugInstalled('vim-airline') && PlugInstalled('asyncrun.vim')
  let g:airline_section_error = airline#section#create_right(['%{g:asyncrun_status}'])
endif

if !exists('g:airline_symbols')
  let g:airline_symbols = {}
endif

if get(g:, 'airline_powerline_fonts', 0)
  let g:airline_left_sep = ''
  let g:airline_left_alt_sep = ''
  let g:airline_right_sep = ''
  let g:airline_right_alt_sep = ''
  let g:airline_symbols.branch = ''
  let g:airline_symbols.readonly = ''
  let g:airline_symbols.linenr = ''
  let g:airline_symbols.notexists = '∄'
  let g:airline_symbols.whitespace = 'Ξ'
else
  let g:airline_left_sep = '▶'
  let g:airline_right_sep = '◀'
endif
