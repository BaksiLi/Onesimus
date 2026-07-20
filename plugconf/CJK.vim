" CJK editing without taking over the user's input method.

" jieba.vim is deliberately lazy: ASCII buffers keep native motion semantics
" and the dictionary is loaded only after Chinese text is encountered.  We
" install mappings ourselves only after the native backend is proven usable,
" so a failed plugin build can never steal w/b/e from Vim.
let g:jieba_vim_lazy = 1
let g:jieba_vim_keymap = 0

let s:jieba_motions = ['w', 'W', 'e', 'E', 'b', 'B', 'ge', 'gE']
let s:jieba_objects = ['iw', 'iW', 'aw', 'aW']
" Match the Han ranges understood by jieba's Rust backend, including 〇,
" compatibility ideographs, radicals, and supplementary-plane extensions.
let s:han_pattern = '[〇⺀-⿕㐀-䶿一-鿿豈-﫿𠀀-𪛟𪜀-𫜿𫝀-𫠟丽-𯨟]'
let s:jieba_loading = 0

" Empty means content-driven loading in every filetype.  Users who keep CJK
" prose in only a few formats can narrow this to, for example, ['markdown'].
let g:onesimus_jieba_filetypes = get(g:, 'onesimus_jieba_filetypes', [])

function! OnesimusJiebaReady() abort
  if !has('python3') || !exists('g:loaded_jieba_vim')
        \ || !exists('*JiebaModelNmap')
    return 0
  endif

  try
    return py3eval("'jieba_vim.navigation' in __import__('sys').modules")
  catch
    return 0
  endtry
endfunction

function! s:UnmapJieba() abort
  for l:key in s:jieba_motions
    for l:mode in ['n', 'x']
      if maparg(l:key, l:mode) ==# '<Plug>(Jieba_'.l:key.')'
        execute l:mode.'unmap '.l:key
      endif
    endfor
    if maparg(l:key, 'o') ==# '<Plug>(Jieba_'.l:key.')'
          \ || maparg(l:key, 'o') =~# 'JiebaOperator'
      execute 'ounmap '.l:key
    endif
  endfor

  for l:key in s:jieba_objects
    if maparg(l:key, 'x') ==# '<Plug>(Jieba_'.l:key.')'
      execute 'xunmap '.l:key
    endif
    if maparg(l:key, 'o') ==# '<Plug>(Jieba_'.l:key.')'
          \ || maparg(l:key, 'o') =~# 'JiebaOperator'
      execute 'ounmap '.l:key
    endif
  endfor

  for l:key in s:jieba_motions + s:jieba_objects
    let l:plug = '<Plug>(Onesimus_native_'.l:key.')'
    if !empty(maparg(l:plug, 'o'))
      execute 'ounmap '.l:plug
    endif
  endfor
endfunction

function! s:JiebaOperator(key) abort
  " vim-surround and other operatorfunc plugins use g@ and expect to receive
  " the motion themselves.  Give those plugins native Vim semantics while
  " keeping d/c/y Chinese-aware.
  return v:operator ==# 'g@'
        \ ? "\<Plug>(Onesimus_native_".a:key.")"
        \ : "\<Plug>(Jieba_".a:key.")"
endfunction

function! OnesimusConfigureJieba() abort
  call s:UnmapJieba()
  if !OnesimusJiebaReady()
    let g:onesimus_jieba_loaded = 0
    return
  endif

  let g:onesimus_jieba_loaded = 1

  for l:key in s:jieba_motions
    for l:mode in ['n', 'x']
      execute l:mode.'map <silent> '.l:key.' <Plug>(Jieba_'.l:key.')'
    endfor
    " Vim 8.2 does not expand a <Plug> returned by a non-recursive <expr>
    " mapping.  The public mapping must therefore be recursive; this private,
    " non-recursive route lets g@ reach the native motion without looping.
    execute 'onoremap <silent> <Plug>(Onesimus_native_'.l:key.') '.l:key
    execute 'omap <silent><expr> '.l:key.' <SID>JiebaOperator('
          \ .string(l:key).')'
  endfor

  for l:key in s:jieba_objects
    execute 'xmap <silent> '.l:key.' <Plug>(Jieba_'.l:key.')'
    execute 'onoremap <silent> <Plug>(Onesimus_native_'.l:key.') '.l:key
    execute 'omap <silent><expr> '.l:key.' <SID>JiebaOperator('
          \ .string(l:key).')'
  endfor
endfunction

function! s:StopJiebaWatchers() abort
  augroup onesimus_jieba
    autocmd!
  augroup END
endfunction

function! OnesimusJiebaLoad(...) abort
  let l:explicit = get(a:000, 0, 0)
  if get(g:, 'onesimus_jieba_loaded', 0) || s:jieba_loading
    return get(g:, 'onesimus_jieba_loaded', 0)
  endif
  if !l:explicit && !empty(get(g:, 'onesimus_jieba_error', ''))
    return 0
  endif
  if !has('python3') || !has_key(get(g:, 'plugs', {}), 'jieba.vim')
    return 0
  endif
  if !isdirectory(get(g:plugs['jieba.vim'], 'dir', ''))
    let g:onesimus_jieba_error =
          \ 'jieba.vim is not installed; run :PlugInstall jieba.vim'
    call s:StopJiebaWatchers()
    return 0
  endif

  let g:onesimus_jieba_error = ''
  let s:jieba_loading = 1
  try
    if !exists('g:loaded_jieba_vim') && exists('*plug#load')
      call plug#load('jieba.vim')
    endif
    call OnesimusConfigureJieba()
  catch
    let g:onesimus_jieba_loaded = 0
    let g:onesimus_jieba_error = v:exception
  finally
    let s:jieba_loading = 0
  endtry

  if get(g:, 'onesimus_jieba_loaded', 0)
    call s:StopJiebaWatchers()
    if exists('*OnesimusTrackOnce')
      call OnesimusTrackOnce('writing.cjk')
    endif
    return 1
  endif
  if empty(get(g:, 'onesimus_jieba_error', ''))
    let g:onesimus_jieba_error =
          \ 'jieba backend unavailable; run :OnesimusJiebaInstall'
  endif
  call s:StopJiebaWatchers()
  return 0
endfunction

function! s:BufferHasHan() abort
  if getline('.') =~# s:han_pattern
    return 1
  endif
  let l:last = min([line('$'), get(g:, 'onesimus_jieba_scan_lines', 300)])
  for l:line in getline(1, l:last)
    if l:line =~# s:han_pattern
      return 1
    endif
  endfor
  return 0
endfunction

function! s:JiebaFiletypeAllowed() abort
  let l:filetypes = get(g:, 'onesimus_jieba_filetypes', [])
  return empty(l:filetypes) || index(l:filetypes, &filetype) >= 0
endfunction

function! s:MaybeLoadJieba() abort
  if get(g:, 'onesimus_jieba_loaded', 0) || !has('python3')
        \ || !s:JiebaFiletypeAllowed()
    return
  endif
  if s:BufferHasHan()
    call OnesimusJiebaLoad()
  endif
endfunction

function! s:MaybeLoadJiebaCurrentLine() abort
  if !get(g:, 'onesimus_jieba_loaded', 0)
        \ && has('python3') && s:JiebaFiletypeAllowed()
        \ && getline('.') =~# s:han_pattern
    call OnesimusJiebaLoad()
  endif
endfunction

function! OnesimusJiebaInstall() abort
  if !has('python3')
    throw 'jieba.vim needs a Vim build with +python3'
  endif

  let g:onesimus_jieba_error = ''
  try
    if !exists('g:loaded_jieba_vim') && exists('*plug#load')
      call plug#load('jieba.vim')
    endif

    if !exists('*jieba_vim#install')
      throw 'jieba.vim is not installed; run :PlugInstall jieba.vim'
    endif

    call jieba_vim#install()
    call OnesimusConfigureJieba()
    if get(g:, 'onesimus_jieba_loaded', 0)
      call s:StopJiebaWatchers()
      return
    endif
    throw 'jieba backend did not become ready'
  catch
    let g:onesimus_jieba_loaded = 0
    let g:onesimus_jieba_error = v:exception
    " :throw reserves the Vim/Vim(...) prefix for internal exceptions.
    throw 'Onesimus jieba install: '.g:onesimus_jieba_error
  endtry
endfunction

function! s:ManualJiebaInstall() abort
  try
    call OnesimusJiebaInstall()
  catch
    echohl WarningMsg
    echomsg 'Onesimus: '.v:exception
    echohl None
  endtry
endfunction
command! OnesimusJiebaInstall call <SID>ManualJiebaInstall()

function! s:ManualJiebaEnable() abort
  if !OnesimusJiebaLoad(1)
    echohl WarningMsg
    echomsg 'Onesimus: '.get(g:, 'onesimus_jieba_error',
          \ 'jieba.vim could not be loaded')
    echohl None
  endif
endfunction
command! OnesimusJiebaEnable call <SID>ManualJiebaEnable()

function! s:ConfigureCJKProse() abort
  " Let gq and 'textwidth' break between CJK characters, and keep :join from
  " inserting spaces around them.  These are Vim's native multibyte flags.
  setlocal formatoptions+=mM

  " Preserve English words while displaying wrapped prose.  Wrapped Markdown
  " list items align with their text rather than gaining arbitrary padding.
  setlocal wrap linebreak breakindent
  setlocal breakindentopt=list:-1

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

  if !get(b:, 'onesimus_cjk_prose', 0)
    let l:undo = 'setlocal formatoptions< wrap< linebreak< breakindent< matchpairs< '
          \ . 'breakindentopt< | unlet! b:surround_113 b:surround_81 '
          \ . 'b:onesimus_cjk_prose'
    let b:undo_ftplugin = empty(get(b:, 'undo_ftplugin', ''))
          \ ? l:undo : b:undo_ftplugin.' | '.l:undo
    let b:onesimus_cjk_prose = 1
  endif
endfunction

let g:onesimus_prose_filetypes = get(g:, 'onesimus_prose_filetypes',
      \ ['gitcommit', 'markdown', 'text', 'tex'])

augroup onesimus_cjk_prose
  autocmd!
  execute 'autocmd FileType '.join(g:onesimus_prose_filetypes, ',')
        \ .' call <SID>ConfigureCJKProse()'
augroup END

augroup onesimus_jieba
  autocmd!
  if has('python3') && has_key(get(g:, 'plugs', {}), 'jieba.vim')
        \ && !get(g:, 'onesimus_jieba_loaded', 0)
        \ && empty(get(g:, 'onesimus_jieba_error', ''))
    autocmd BufReadPost,BufNewFile * call <SID>MaybeLoadJieba()
    autocmd FileType * call <SID>MaybeLoadJieba()
    " Loading the Python/Rust bridge is synchronous.  Never put that first-load
    " cost on an Insert-mode cursor move or IME commit; activate as soon as the
    " user returns to Normal mode instead.
    autocmd CursorMoved,TextChanged,InsertLeave *
          \ call <SID>MaybeLoadJiebaCurrentLine()
  endif
augroup END

" Also makes :source $MYVIMRC take effect immediately after startup.
call OnesimusConfigureJieba()
if index(g:onesimus_prose_filetypes, &filetype) >= 0
  call s:ConfigureCJKProse()
endif
call s:MaybeLoadJieba()
