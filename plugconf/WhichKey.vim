" TODO: local keys for specific filetype
" ------ Misc ------
let g:which_key_map = {
  \ 'h' : 'Open Onesimos Documentation',
  \ 's' : { 'name' : 'Source', 'd' : 'Source Dotfile' },
  \ }

" ------ Toggle ------
let g:which_key_map['t'] = {
  \ 'name' : '+toggle',
  \ 'r' : 'Toggle Relative Numbering',
  \ 'w' : ['WPModeToggle', 'Toggle Word Processing Mode'],
  \ 'i' : ['IndentLinesToggle', 'Toggle Indent Indicator'],
  \ 'p' : ['ParenthesisToggle', 'Toggle Parenthesis Indicator'],
  \ }

" ------ Fuzzy finder ------
let g:which_key_map['f'] = {
  \ 'name' : '+Fuzzy',
  \ 'f' : 'In Situ',
  \ 'm' : 'Most Recent Files',
  \ 'b' : 'Buffer',
  \ 't' : 'Tags',
  \ 'l' : 'Line',
  \ }

" ------ Current File ------
let g:which_key_map['e'] = {
  \ 'name' : '+File',
  \ 'd' : 'Edit Dotfile',
  \ 'r' : ['Rename', 'Rename File'],
  \ 't' : 'Create Tags',
  \ 'p' : [':read !pbpaste', 'Paste Clipboard'],
  \ }

" ------ Window ------
let g:window_resize_f = 15

let g:which_key_map['w'] = {
  \ 'name' : '+Window',
  \ '-' : ['<C-W>s', 'Split Below'],
  \ '|' : ['<C-W>v', 'Split Right'],
  \ 'H' : [':vert res -'.g:window_resize_f, 'Resize Left'],
  \ 'J' : [':res +'.g:window_resize_f, 'Resize Down'],
  \ 'K' : [':res -'.g:window_resize_f, 'Resize Up'],
  \ 'L' : [':vert res +'.g:window_resize_f, 'Resize Left'],
  \ }

" ------ Version Control ------
let g:which_key_map['v'] = {
      \ 'name' : '+Git',
      \ 'b' : ['Gblame', 'fugitive-blame'],
      \ 'C' : ['Gcommit', 'fugitive-commit'],
      \ 'd' : ['Gdiff', 'fugitive-diff'],
      \ 'e' : ['Gedit', 'fugitive-edit'],
      \ 'l' : ['Glog', 'fugitive-log'],
      \ 'r' : ['Gread', 'fugitive-read'],
      \ 's' : ['Gstatus', 'fugitive-status'],
      \ 'w' : ['Gwrite', 'fugitive-write'],
      \ 'p' : ['Git push', 'fugitive-push'],
      \ }

" ------ Onesimos Settings ------
" TODO: unicode decoration
let g:which_key_map['\'] = {
  \ 'name' : 'Onesimos Vim Settings',
  \ 'u' : {
    \ 'name' : 'User Interface',
    \ 'c' : [':Leaderf colorscheme', 'Switch Colour Scheme'],
    \ 'b' : ['ToggleBackground', 'Toggle Background Colour']
    \ }
  \ }

" ------ WhichKey Settings ------
let g:which_key_use_floating_win = 1

call which_key#register('\', 'g:which_key_map')

nnoremap <silent> <leader> :<c-u>WhichKey '\'<CR>
vnoremap <silent> <leader> :<c-u>WhichKey '\'<CR>
