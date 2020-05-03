" TODO: recent git commit funcref
let g:startify_lists = [
      \ { 'type': 'files', 'header': ['    Recent Files'] },
      \ { 'type': 'dir', 'header': ['    Recent Directory Edit ('.getcwd().')']},
      \ { 'type': 'sessions', 'header': ['    Sessions']},
      \ { 'type': 'bookmarks', 'header': ['    Bookmarks']},
      \ ]

let g:startify_bookmarks = [{'d': $MYVIMDOT},]
let g:startify_files_number = 5
let g:startify_change_to_dir = 1

" TODO: Disable indentLine for a moment 
" if g:indentLine_enabled
" IndentLinesToggle
" endif

let g:ascii_art = [
      \ '                           _ooOoo                ',
      \ '                          o8888888o                ',
      \ '                          88" . "88                ',
      \ '                          (| -_- |)                ',
      \ '                          O\  =  /O                ',
      \ "                       ____/`---'\____             ",
      \ "                     .'  \\\\|     |//  `.             ",
      \ '                    /  \\|||  :  |||//  \            ',
      \ '                   /  _||||| -:- |||||_  \           ',
      \ "                   |   | \\\\\\  -  /'| |   |            ",
      \ "                   |  _|  `\\\\`---'//  |_/ |            ",
      \ "                   \\ .-\\__ \\\\-. -'__/-.  /           ",
      \ "                 ___`. .'  /--.--\\  `. .'___            ",
      \ "              ./ / <  `.___\\_<|>_/___.' _> \\ \\.         ",
      \ "             | | :  `- \\`. ;`. _/; .'/ /  .' ; |          ",
      \ "             \  \ `-.   \\_\\_`. _.'_/_/  -' _.' /         ",
      \ "   ===========`-.`___`-.__\\ \\___/ /__.-'_.'_.-'=============   ",
      \ "                           `=--=-'                         ",
      \]

let g:startify_custom_header = startify#pad(g:ascii_art)
