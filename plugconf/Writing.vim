" Shared prose display; language-specific syntax and renderers stay with their hosts.

let g:onesimus_prose_filetypes = get(g:, 'onesimus_prose_filetypes',
      \ ['gitcommit', 'markdown', 'text', 'tex', 'cogitatum'])

" Keep punctuation with its word instead of offering it as a wrap boundary.
" 'breakat' is global; preserve an explicitly customized character set.
if &breakat ==# " \t!@*-+;:,./?"
  let &breakat = " \t"
endif

function! OnesimusUnmapProseArrows() abort
  for [l:mode, l:leased] in [
        \ ['n', {'<Up>': 'gk', '<Down>': 'gj', '<Left>': 'h', '<Right>': 'l'}],
        \ ['i', {'<Up>': '<C-O>gk', '<Down>': '<C-O>gj'}],
        \ ['x', {'<Up>': 'gk', '<Down>': 'gj'}]]
    for [l:key, l:rhs] in items(l:leased)
      let l:mapping = maparg(l:key, l:mode, 0, 1)
      if get(l:mapping, 'buffer', 0) && get(l:mapping, 'rhs', '') ==# l:rhs
        execute l:mode.'unmap <buffer> '.l:key
      endif
    endfor
  endfor
endfunction

function! OnesimusEnforceProseSoftWrap(...) abort
  if index(g:onesimus_prose_filetypes, &l:filetype) < 0
    return
  endif

  " Width-based insertion applies to comments as well as ordinary text.
  " Explicit gq/F6 remain available; no typing or EditorConfig reload reflows.
  setlocal textwidth=0 wrapmargin=0
  setlocal formatoptions-=t
  setlocal formatoptions-=c
  setlocal formatoptions-=a
  return 0
endfunction

function! s:ConfigureWritingDisplay() abort
  " Let gq and 'textwidth' break between CJK characters, and keep :join from
  " inserting spaces around them.  These are Vim's native multibyte flags.
  setlocal formatoptions+=mM

  " Physical newlines are authorial structure.  Screen wrapping stays soft;
  " neither typing nor focus mode hard-wraps prose behind the author's back.
  call OnesimusEnforceProseSoftWrap()

  " Preserve English words while displaying wrapped prose.  Wrapped Markdown
  " list items align with their text rather than gaining arbitrary padding.
  setlocal wrap linebreak breakindent
  setlocal breakindentopt=list:-1
  let &l:showbreak = '↳ '

  " Make Vim's native % motion understand common full-width prose pairs.
  for l:pair in ['（:）', '「:」', '『:』', '【:】', '《:》']
    if index(split(&l:matchpairs, ','), l:pair) < 0
      let &l:matchpairs .= ','.l:pair
    endif
  endfor

  " vim-surround shortcuts for the two common Chinese quotation levels:
  " ysiwq -> 「word」, ysiwQ -> 『word』.
  let b:surround_113 = "「\r」"
  let b:surround_81 = "『\r』"

  " Touch terminals commonly send arrow keys.  In prose, vertical arrows
  " follow displayed rows while mnemonic h/j/k/l remain available.
  nnoremap <silent><buffer> <Up> gk
  nnoremap <silent><buffer> <Down> gj
  nnoremap <silent><buffer> <Left> h
  nnoremap <silent><buffer> <Right> l
  inoremap <silent><buffer> <Up> <C-O>gk
  inoremap <silent><buffer> <Down> <C-O>gj
  xnoremap <silent><buffer> <Up> gk
  xnoremap <silent><buffer> <Down> gj

  if !get(b:, 'onesimus_writing_display', 0)
    let l:undo = 'setlocal formatoptions< textwidth< wrapmargin< wrap< linebreak< breakindent< matchpairs< '
          \ . 'breakindentopt< showbreak< | unlet! b:surround_113 b:surround_81 '
          \ . 'b:onesimus_writing_display | call OnesimusUnmapProseArrows()'
    let b:undo_ftplugin = empty(get(b:, 'undo_ftplugin', ''))
          \ ? l:undo : b:undo_ftplugin.' | '.l:undo
    let b:onesimus_writing_display = 1
  endif
endfunction

augroup onesimus_writing_display
  autocmd!
  execute 'autocmd FileType '.join(g:onesimus_prose_filetypes, ',')
        \ .' call <SID>ConfigureWritingDisplay()'
augroup END

if index(g:onesimus_prose_filetypes, &filetype) >= 0
  call s:ConfigureWritingDisplay()
endif

function! OnesimusIsWritingBuffer(bufnr) abort
  return bufexists(a:bufnr) && getbufvar(a:bufnr, '&buftype') ==# ''
        \ && (getbufvar(a:bufnr, '&filetype') ==# 'bib'
        \   || index(g:onesimus_prose_filetypes,
        \     getbufvar(a:bufnr, '&filetype')) >= 0
        \   || (empty(getbufvar(a:bufnr, '&filetype'))
        \     && !empty(get(g:, 'onesimus_wordproc_state', {}))))
endfunction
