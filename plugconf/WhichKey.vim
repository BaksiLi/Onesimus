let g:which_key_map = {
  \ 'h' : 'Open Onesimos Documentation',
  \ 's' : { 'name' : 'Source', 'd' : 'Source Dotfile' },
  \ }

let g:which_key_map['t'] = {
  \ 'name' : '+toggle',
  \ 'r' : 'Toggle Relative Numbering',
  \ 'i' : ['IndentLinesToggle', 'Toggle Indent Indicator'],
  \ 'p' : ['RainbowToggle', 'Toggle Parenthesis Indicator']
  \ }

let g:which_key_map['f'] = {
  \ 'name' : '+Fuzzy',
  \ 'f' : 'In Situ',
  \ 'm' : 'Most Recent Files',
  \ 'b' : 'Buffer',
  \ 't' : 'Tags',
  \ 'l' : 'Line',
  \ }

let g:which_key_map['e'] = { 
  \ 'name' : '+File', 
  \ 'd' : 'Edit Dotfile',
  \ 'r' : ['Rename', 'Rename File'],
  \ 't' : 'Create Tags',
  \ }

" TODO: more
let g:which_key_map['w'] = {
  \ 'name' : '+Window',
  \ '-' : ['<C-W>s'     , 'split-window-below']    ,
  \ '|' : ['<C-W>v'     , 'split-window-right']    ,
  \ }

let g:which_key_map['v'] = {
      \ 'name' : '+Git' ,
      \ 'b' : ['Gblame'                 , 'fugitive-blame']             ,
      \ 'C' : ['Gcommit'                , 'fugitive-commit']            ,
      \ 'd' : ['Gdiff'                  , 'fugitive-diff']              ,
      \ 'e' : ['Gedit'                  , 'fugitive-edit']              ,
      \ 'l' : ['Glog'                   , 'fugitive-log']               ,
      \ 'r' : ['Gread'                  , 'fugitive-read']              ,
      \ 's' : ['Gstatus'                , 'fugitive-status']            ,
      \ 'w' : ['Gwrite'                 , 'fugitive-write']             ,
      \ 'p' : ['Git push'               , 'fugitive-push']              ,
      \ }

" TODO: unicode decoration
let g:which_key_map['\'] = {
  \ 'name' : 'Onesimos Vim Settings',
  \ 'u' : {
    \ 'name' : 'User Interface',
    \ 'c' : [':Leaderf colorscheme', 'Switch Colour Scheme'],
    \ }
  \ }

let g:which_key_use_floating_win = 1

call which_key#register('\', 'g:which_key_map')  

nnoremap <silent> <leader> :<c-u>WhichKey '\'<CR>
vnoremap <silent> <leader> :<c-u>WhichKey '\'<CR>
