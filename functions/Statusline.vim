" Status and tab lines from Vim's own 'statusline' and 'tabline'. They
" replaced vim-airline, which rebuilt about eighty highlight groups at every
" start and mode change: some 25 ms of a 65 ms start, and more on a slow
" machine over SSH. These lines only read values that are cached or cheap.
"
" The bundled schemes define every group used here (see
" scripts/build_themes.vim); any other scheme falls back to its own groups.

set laststatus=2

let s:modes = {
      \ 'n': ['NORMAL', 'Normal'], 'i': ['INSERT', 'Insert'],
      \ 'R': ['REPLACE', 'Replace'], 'v': ['VISUAL', 'Visual'],
      \ 'V': ['V-LINE', 'Visual'], "\<C-v>": ['V-BLOCK', 'Visual'],
      \ 's': ['SELECT', 'Visual'], 'S': ['S-LINE', 'Visual'],
      \ "\<C-s>": ['S-BLOCK', 'Visual'], 'c': ['COMMAND', 'Normal'],
      \ 't': ['TERMINAL', 'Insert']}

function! s:Defaults() abort
  for l:tone in ['Normal', 'Insert', 'Visual', 'Replace']
    execute 'highlight default link OnesimusMode'.l:tone 'PmenuSel'
  endfor
  highlight default link OnesimusStatusB Pmenu
  highlight default link OnesimusStatusWarning WarningMsg
  highlight default link OnesimusStatusError ErrorMsg
endfunction

function! s:Thousands(number) abort
  return substitute(a:number, '\d\zs\ze\%(\d\d\d\)\+$', ',', 'g')
endfunction

" fugitive finds each buffer's repository; reading HEAD ourselves avoids
" loading fugitive's 7,000-line autoload at startup. HEAD is re-read only
" when its time stamp changes, so a checkout elsewhere still shows.
function! s:Branch(buf) abort
  let l:dir = getbufvar(a:buf, 'git_dir')
  if empty(l:dir)
    return ''
  endif
  let l:time = getftime(l:dir.'/HEAD')
  let l:cached = getbufvar(a:buf, 'onesimus_head', [-2, ''])
  if l:cached[0] != l:time
    let l:ref = get(readfile(l:dir.'/HEAD', '', 1), 0, '')
    let l:cached = [l:time, l:ref =~# '^ref: '
          \ ? substitute(l:ref, '^ref: \%(refs/heads/\)\=', '', '') : l:ref[:6]]
    call setbufvar(a:buf, 'onesimus_head', l:cached)
  endif
  return l:cached[1]
endfunction

function! s:Hunks(buf) abort
  if !exists('g:loaded_gitgutter')
    return ''
  endif
  let l:counts = gitgutter#hunk#summary(a:buf)
  return join(filter(map(['+', '~', '-'],
        \ 'l:counts[v:key] ? v:val.l:counts[v:key] : ""'), '!empty(v:val)'))
endfunction

" Counted when the text settles, never per redraw: wordcount() reads the
" whole buffer.
function! s:CountWords() abort
  if index(get(g:, 'onesimus_prose_filetypes', []), &filetype) >= 0
    let b:onesimus_words = s:Thousands(wordcount().words).' words'
  else
    unlet! b:onesimus_words
  endif
endfunction

" Problem counts with the first line of each kind, as W:12 (L40).
function! s:Problems(buf) abort
  if !exists('g:loaded_ale')
    return ''
  endif
  let l:count = ale#statusline#Count(a:buf)
  let l:line = ''
  for [l:mark, l:group, l:kinds] in [
        \ ['W', 'Warning', ['warning', 'style_warning', 'info']],
        \ ['E', 'Error', ['error', 'style_error']]]
    let l:total = 0
    let l:first = 0
    for l:kind in l:kinds
      let l:total += l:count[l:kind]
      let l:at = get(ale#statusline#FirstProblem(a:buf, l:kind), 'lnum', 0)
      let l:first = l:at && (!l:first || l:at < l:first) ? l:at : l:first
    endfor
    if l:total
      let l:line .= printf('%%#OnesimusStatus%s# %s:%d (L%d) ',
            \ l:group, l:mark, l:total, l:first)
    endif
  endfor
  return l:line
endfunction

function! s:Name(buf) abort
  let l:type = getbufvar(a:buf, '&buftype')
  if l:type ==# 'quickfix'
    return getwinvar(g:statusline_winid, 'quickfix_title', 'Quickfix')
  elseif l:type ==# 'terminal'
    return 'Terminal'
  endif
  return '%f'
endfunction

function! OnesimusStatusline() abort
  let l:buf = winbufnr(g:statusline_winid)
  " Other windows: StatusLineNC throughout, name and state only.
  if g:statusline_winid != win_getid()
    return ' %<'.s:Name(l:buf).'%( %m%r%)'
  endif

  let [l:label, l:tone] = get(s:modes, mode(), ['NORMAL', 'Normal'])
  let l:tone = '%#OnesimusMode'.l:tone.'#'
  let l:line = l:tone.' '.l:label.(&paste ? ' PASTE' : '').' '
  let l:git = join(filter([s:Branch(l:buf), s:Hunks(l:buf)], '!empty(v:val)'))
  if !empty(l:git)
    let l:line .= '%#OnesimusStatusB# '.l:git.' '
  endif

  let l:notes = ''
  for l:Note in ['OnesimusSourceStatusline', 'OnesimusTexStatusline']
    if exists('*'.l:Note)
      let l:text = call(l:Note, [])
      let l:notes .= empty(l:text) ? '' : ' '.l:text
    endif
  endfor
  let l:line .= '%* %<'.s:Name(l:buf).'%( %m%r%)'.l:notes.' %='

  let l:encoding = (empty(&fileencoding) ? &encoding : &fileencoding)
        \ .'['.&fileformat.']'
  let l:line .= join(filter([&filetype,
        \ l:encoding ==# 'utf-8[unix]' ? '' : l:encoding], '!empty(v:val)'))
  let l:line .= ' '.l:tone.' '.get(b:, 'onesimus_words', '')
        \ .(exists('b:onesimus_words') ? '  ' : '').'%p%% %l/%L:%v '

  " Only a running or failed job: success needs no reminder.
  let l:job = get(g:, 'asyncrun_status', '')
  if l:job ==# 'running'
    let l:line .= '%#OnesimusStatusB# running '
  elseif l:job ==# 'failure'
    let l:line .= '%#OnesimusStatusError# run failed '
  endif
  return l:line.s:Problems(l:buf)
endfunction

" The tab line lists buffers (or tab pages, when there are several). With a
" single buffer it would only repeat the status line, so it hides and gives
" the row back, which matters on a phone.
function! s:Listed(...) abort
  let l:gone = a:0 ? a:1 : -1
  return filter(range(1, bufnr('$')), 'buflisted(v:val) && v:val != l:gone')
endfunction

function! s:ShowTabline(gone) abort
  let &showtabline = tabpagenr('$') > 1 || len(s:Listed(a:gone)) > 1 ? 2 : 0
endfunction

function! s:Label(buf, names) abort
  let l:path = bufname(a:buf)
  if empty(l:path)
    return '[No Name]'
  endif
  let l:tail = fnamemodify(l:path, ':t')
  " Two buffers with one name show their directories.
  return count(a:names, l:tail) > 1 ? fnamemodify(l:path, ':p:h:t').'/'.l:tail : l:tail
endfunction

function! OnesimusTabline() abort
  if tabpagenr('$') > 1
    let l:buffers = map(range(1, tabpagenr('$')),
          \ 'tabpagebuflist(v:val)[tabpagewinnr(v:val) - 1]')
    let l:current = tabpagenr() - 1
    let l:kind = 'tabs'
  else
    let l:buffers = s:Listed()
    let l:current = index(l:buffers, bufnr(''))
    let l:kind = 'buffers'
  endif
  let l:names = map(copy(l:buffers), 'fnamemodify(bufname(v:val), ":t")')
  let l:items = []
  for l:i in range(len(l:buffers))
    let l:buf = l:buffers[l:i]
    let l:items += [[l:i == l:current ? 'TabLineSel' : 'TabLine',
          \ ' '.s:Label(l:buf, l:names).(getbufvar(l:buf, '&modified') ? ' +' : '').' ']]
  endfor

  " Keep the current item in view: drop the farthest items until all fit.
  let l:room = &columns - strdisplaywidth(l:kind) - 4
  let [l:first, l:last] = [0, len(l:items) - 1]
  while l:first < l:last && eval(join(map(l:items[l:first : l:last],
        \ 'strdisplaywidth(v:val[1])'), '+')) > l:room
    if l:current - l:first > l:last - l:current
      let l:first += 1
    else
      let l:last -= 1
    endif
  endwhile

  let l:line = l:first > 0 ? '%#TabLineFill#‹' : ''
  for l:i in range(l:first, l:last)
    let [l:group, l:text] = l:items[l:i]
    let l:text = substitute(l:text, '%', '%%', 'g')
    let l:line .= (l:kind ==# 'tabs' ? '%'.(l:i + 1).'T' : '')
          \ .'%#'.l:group.'#'.l:text
  endfor
  let l:line .= l:last < len(l:items) - 1 ? '%#TabLineFill#›' : ''
  return l:line.'%#TabLineFill#%T%=%#OnesimusModeVisual# '.l:kind.' '
endfunction

set statusline=%!OnesimusStatusline()
set tabline=%!OnesimusTabline()

augroup onesimus_statusline
  autocmd!
  autocmd ColorScheme * call <SID>Defaults()
  autocmd BufEnter,BufWritePost,InsertLeave,TextChanged,FileType *
        \ call <SID>CountWords()
  autocmd VimEnter,BufAdd,TabNew,TabClosed * call <SID>ShowTabline(-1)
  autocmd BufDelete,BufWipeout * call <SID>ShowTabline(str2nr(expand('<abuf>')))
  autocmd OptionSet buflisted call <SID>ShowTabline(-1)
augroup END
call s:Defaults()
