" Contrast policy of the bundled schemes (see scripts/build_themes.vim).
" Run with: vim -Nu tests/themes.vim -i NONE -n -es
set nocompatible termguicolors
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^='.fnameescape(s:root.'/packages/themes')
syntax on

function! s:Luminance(hex) abort
  let l:sum = 0.0
  for [l:at, l:weight] in [[1, 0.2126], [3, 0.7152], [5, 0.0722]]
    let l:c = str2nr(a:hex[l:at : l:at + 1], 16) / 255.0
    let l:c = l:c <= 0.03928 ? l:c / 12.92 : pow((l:c + 0.055) / 1.055, 2.4)
    let l:sum += l:weight * l:c
  endfor
  return l:sum
endfunction

" WCAG 2.2 contrast ratio of a group's text against its own background.
function! s:Ratio(group) abort
  let l:id = synIDtrans(hlID(a:group))
  let l:normal = synIDtrans(hlID('Normal'))
  let l:fg = synIDattr(l:id, 'fg#', 'gui')
  let l:bg = synIDattr(l:id, 'bg#', 'gui')
  let l:fg = empty(l:fg) ? synIDattr(l:normal, 'fg#', 'gui') : l:fg
  let l:bg = empty(l:bg) ? synIDattr(l:normal, 'bg#', 'gui') : l:bg
  let [l:a, l:b] = [s:Luminance(l:fg), s:Luminance(l:bg)]
  return (max([l:a, l:b]) + 0.05) / (min([l:a, l:b]) + 0.05)
endfunction

" Text the writer reads: SC 1.4.3. Marks carrying information: SC 1.4.11.
let s:text = ['Normal', 'Comment', 'Folded', 'Pmenu', 'PmenuSel', 'WildMenu',
      \ 'Search', 'IncSearch', 'Visual', 'MoreMsg', 'Title', 'CursorLineNr',
      \ 'QuickFixLine', 'StatusLine', 'TabLine', 'TabLineSel', 'OnesimusStatusB',
      \ 'OnesimusModeNormal', 'OnesimusModeInsert', 'OnesimusModeVisual',
      \ 'OnesimusModeReplace', 'OnesimusStatusWarning', 'OnesimusStatusError']
let s:marks = ['LineNr', 'ALEErrorSign', 'ALEWarningSign', 'ErrorMsg',
      \ 'DiffDelete', 'DiffText']

for [s:name, s:background] in [['gruvbox', 'dark'], ['gruvbox', 'light'],
      \ ['nord', 'dark']]
  let &background = s:background
  execute 'colorscheme' s:name
  for [s:groups, s:least] in [[s:text, 4.5], [s:marks, 3.0]]
    for s:group in s:groups
      let s:ratio = s:Ratio(s:group)
      call assert_true(s:ratio >= s:least, printf('%s %s: %s is %.2f:1, below %.1f:1',
            \ s:name, s:background, s:group, s:ratio, s:least))
    endfor
  endfor
endfor

if !empty(v:errors)
  call writefile(v:errors, '/dev/stderr')
  cquit
endif
qall!
