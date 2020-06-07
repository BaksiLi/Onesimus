let g:ale_sign_column_always = 1
let b:ale_linters = {
\ 'javascript': ['eslint'],
\ 'python': ['flake8'],
\ 'Markdown': ['mdl'],
\ 'LaTeX': ['chktex'],
\ 'vim': ['vint'],
\ 'bash': ['shellcheck'],
\}
nmap ]a <Plug>(ale_next_wrap)
nmap [a <Plug>(ale_previous_wrap)

" Autoformat
let g:ale_fixers = {
\ '*': ['trim_whitespace', 'remove_trailing_lines'],
\ 'python': ['isort', 'yapf'],
\ 'javascript': ['eslint'],
\}

" Completion
" replaced by CoC
