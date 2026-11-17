" Regenerate packages/themes/colors/{gruvbox,nord}.vim from the upstream
" schemes, which no longer change: morhetz/gruvbox (2020) and the archived
" nordtheme/vim (2023). Each output is the scheme's result as plain
" :highlight commands, so loading it runs no option logic or helper calls.
"
"   GRUVBOX=~/.vim/bundle/gruvbox NORD=~/.vim/bundle/nord-vim \
"     vim -Nu NONE -i NONE -es -S scripts/build_themes.vim
"
" GUI attributes come from the upstream run as a GUI would (italic on), and
" cterm attributes from the run as a terminal would; with 'termguicolors' a
" terminal takes gui colours but cterm attributes. The script then reloads
" each result, both fresh and after another scheme, and fails unless every
" group matches upstream plus the refinements below.
set nocompatible encoding=utf-8 termguicolors
syntax on
let s:root = expand('<sfile>:p:h:h').'/packages/themes/colors'
let s:upstream = {'gruvbox': expand($GRUVBOX), 'nord': expand($NORD)}
" Options Onesimus has always set, and the ones that differ by context.
let s:options = {'gruvbox': {'gruvbox_improved_warnings': 1},
      \ 'nord': {}}
let s:italic = {'gruvbox': 'gruvbox_italic', 'nord': 'nord_italic'}
let s:gui = ['gui', 'guifg', 'guibg', 'guisp']
let s:cterm = ['term', 'cterm', 'ctermfg', 'ctermbg']

" Onesimus refinements, applied on top of upstream. Contrast follows WCAG 2.2:
" text the writer reads (comments, folded summaries, menus, messages) gets at
" least 4.5:1 (SC 1.4.3), and marks that carry information (line numbers,
" signs) at least 3:1 (SC 1.4.11). Decoration such as NonText, the ↳ wrap
" marker and split bars stays quiet on purpose. Each new colour is the
" smallest step along the theme's own grey-to-foreground (or hue-to-
" foreground) line that reaches the ratio, so the schemes keep their look.
" tests/themes.vim checks the ratios. Only gui colours change: Onesimus runs
" terminals with 'termguicolors'.
"
" The status and tab lines (functions/Statusline.vim) keep the palettes of
" the airline themes these schemes shipped with, lifted to the same ratios.
" StatusLineNC is exempt: SC 1.4.3 excludes inactive interface parts. Its
" upstream cterm=reverse goes, because with 'termguicolors' a terminal still
" applies cterm attributes and would swap these gui colours.
function! s:Bars(p) abort
  let l:lines = [
        \ 'hi StatusLine gui=NONE cterm=NONE guifg='.a:p.line[0].' guibg='.a:p.line[1],
        \ 'hi StatusLineNC gui=NONE cterm=NONE guifg='.a:p.inactive[0].' guibg='.a:p.inactive[1],
        \ 'hi OnesimusStatusB guifg='.a:p.b[0].' guibg='.a:p.b[1],
        \ 'hi OnesimusStatusWarning guifg='.a:p.ink.' guibg='.a:p.warning,
        \ 'hi OnesimusStatusError guifg='.a:p.error[0].' guibg='.a:p.error[1],
        \ 'hi TabLineFill gui=NONE cterm=NONE guifg='.a:p.fill.' guibg='.a:p.fill,
        \ 'hi clear TabLine', 'hi link TabLine OnesimusStatusB',
        \ 'hi clear TabLineSel', 'hi link TabLineSel OnesimusModeNormal']
  for [l:tone, l:accent] in items(a:p.modes)
    call add(l:lines, 'hi OnesimusMode'.l:tone
          \ .' gui=bold cterm=bold guifg='.a:p.ink.' guibg='.l:accent)
  endfor
  return l:lines
endfunction

let s:refine = {
      \ 'gruvbox dark': [
      \   'hi Comment guifg=#9b8c7a',
      \   'hi Folded guifg=#afa088',
      \   'hi PmenuSel guifg=#282828',
      \   'hi clear WildMenu', 'hi link WildMenu PmenuSel']
      \ + s:Bars({'ink': '#282828', 'fill': '#282828',
      \   'line': ['#afa088', '#3c3836'], 'inactive': ['#7c6f64', '#3c3836'],
      \   'b': ['#c7b89a', '#504945'], 'warning': '#fe8019',
      \   'error': ['#1d2021', '#fb4934'], 'modes': {'Normal': '#a89984',
      \   'Insert': '#83a598', 'Visual': '#fe8019', 'Replace': '#8ec07c'}}),
      \ 'gruvbox light': [
      \   'hi Comment guifg=#776c61',
      \   'hi Title guifg=#757010',
      \   'hi Folded guifg=#695f56',
      \   'hi LineNr guifg=#928374',
      \   'hi CursorLineNr guifg=#7f5a23',
      \   'hi MoreMsg guifg=#92641e',
      \   'hi ALEWarningSign guifg=#aa7017',
      \   'hi PmenuSel guifg=#fbf1c7',
      \   'hi clear WildMenu', 'hi link WildMenu PmenuSel',
      \   'hi Search guifg=#d79921 guibg=#282828',
      \   'hi QuickFixLine guifg=#d79921 guibg=#282828',
      \   'hi DiffText guifg=#d79921 guibg=#282828']
      \ + s:Bars({'ink': '#fbf1c7', 'fill': '#fbf1c7',
      \   'line': ['#695f56', '#ebdbb2'], 'inactive': ['#a89984', '#ebdbb2'],
      \   'b': ['#59514b', '#d5c4a1'], 'warning': '#af3a03',
      \   'error': ['#fbf1c7', '#9d0006'], 'modes': {'Normal': '#786b61',
      \   'Insert': '#076678', 'Visual': '#af3a03', 'Replace': '#417957'}}),
      \ 'nord dark': [
      \   'hi Comment guifg=#929cb0',
      \   'hi Folded guifg=#a7aebd',
      \   'hi LineNr guifg=#757d8f',
      \   'hi PmenuSel guifg=#2e3440 guibg=#88c0d0',
      \   'hi IncSearch guifg=#2e3440 guibg=#81a1c1']
      \ + s:Bars({'ink': '#2e3440', 'fill': '#2e3440',
      \   'line': ['#e5e9f0', '#4c566a'], 'inactive': ['#d8dee9', '#3b4252'],
      \   'b': ['#2e3440', '#81a1c1'], 'warning': '#ebcb8b',
      \   'error': ['#2e3440', '#cf888f'], 'modes': {'Normal': '#88c0d0',
      \   'Insert': '#a3be8c', 'Visual': '#8fbcbb', 'Replace': '#a3be8c'}})}
" Command-line completion shows the same selection as the popup menu.
" Gruvbox light draws Search and its kin reversed: guibg there is the text.
" Its dark-yellow mark failed both ways (cream text at 3.3:1); a highlighter
" yellow with dark text reads at 5.9:1 and still stands out by hue.

function! s:Groups() abort
  let l:groups = {}
  for l:group in hlget()
    let l:entry = {}
    for l:key in s:gui + s:cterm + ['linksto']
      if has_key(l:group, l:key)
        let l:value = l:group[l:key]
        let l:entry[l:key] = type(l:value) == v:t_dict
              \ ? join(sort(keys(l:value)), ',') : l:value
      endif
    endfor
    let l:groups[l:group.name] = l:entry
  endfor
  return l:groups
endfunction

function! s:Fresh(background) abort
  highlight clear
  unlet! g:colors_name g:terminal_ansi_colors
  let &background = a:background
  return s:Groups()
endfunction

function! s:Upstream(name, background, italic) abort
  call s:Fresh(a:background)
  for l:var in keys(s:options) + values(s:italic)
    execute 'unlet! g:'.l:var
  endfor
  for [l:var, l:value] in items(s:options[a:name])
    let g:[l:var] = l:value
  endfor
  let g:[s:italic[a:name]] = a:italic
  execute 'colorscheme '.a:name
  for l:command in get(s:refine, a:name.' '.a:background, [])
    execute l:command
  endfor
  let l:ansi = get(g:, 'terminal_ansi_colors', [])
  return [s:Groups(), l:ansi]
endfunction

" Upstream as a GUI shows it, merged with upstream as a terminal shows it.
function! s:Expected(name, background) abort
  let [l:gui, l:ansi] = s:Upstream(a:name, a:background, 1)
  let [l:term, l:_] = s:Upstream(a:name, a:background, 0)
  let l:groups = {}
  for l:name in keys(l:term)
    let l:groups[l:name] = filter(copy(l:term[l:name]), 'index(s:gui, v:key) < 0')
    call extend(l:groups[l:name],
          \ filter(copy(get(l:gui, l:name, {})), 'index(s:gui, v:key) >= 0'))
  endfor
  return [l:groups, l:ansi]
endfunction

" Commands turning the default groups into the expected ones.
function! s:Commands(base, groups) abort
  let l:lines = []
  for l:name in sort(keys(a:groups))
    let [l:old, l:new] = [get(a:base, l:name, {}), a:groups[l:name]]
    if l:old ==# l:new | continue | endif
    " Attributes set after a link drop it, and a link keeps the attributes
    " already there (as lCursor keeps its defaults), so attributes go first.
    let l:attrs = filter(copy(l:new), 'v:key !=# "linksto"')
    let l:before = filter(copy(l:old), 'v:key !=# "linksto"')
    if has_key(l:new, 'linksto') && l:attrs ==# l:before
      call add(l:lines, 'hi! link '.l:name.' '.l:new.linksto)
      continue
    endif
    if has_key(l:new, 'linksto') && empty(l:attrs)
      call add(l:lines, 'hi clear '.l:name)
      call add(l:lines, 'hi! link '.l:name.' '.l:new.linksto)
      continue
    endif
    if has_key(l:old, 'linksto')
      call add(l:lines, 'hi! link '.l:name.' NONE')
    endif
    let l:words = []
    for l:key in s:cterm + s:gui
      if has_key(l:new, l:key)
        call add(l:words, l:key.'='.l:new[l:key])
      elseif has_key(l:old, l:key)
        call add(l:words, l:key.'=NONE')
      endif
    endfor
    call add(l:lines, 'hi '.l:name.' '.join(l:words))
    if has_key(l:new, 'linksto')
      call add(l:lines, 'hi! link '.l:name.' '.l:new.linksto)
    endif
  endfor
  return l:lines
endfunction

function! s:Body(name, background) abort
  let l:base = s:Fresh(a:background)
  let [l:groups, l:ansi] = s:Expected(a:name, a:background)
  let l:lines = s:Commands(l:base, l:groups)
  if !empty(l:ansi)
    call add(l:lines, 'let g:terminal_ansi_colors = '.string(l:ansi))
  endif
  return [l:lines, l:groups]
endfunction

" Each result is checked as Vim starts with it, and as reached from another
" scheme: gruvbox light by toggling 'background', which reloads the scheme.
function! s:Check(name, background, groups) abort
  let l:switches = {'gruvbox dark': 'colorscheme nord | colorscheme gruvbox',
        \ 'gruvbox light': 'set background=dark | colorscheme gruvbox | set background=light',
        \ 'nord dark': 'colorscheme gruvbox | colorscheme nord'}
  for l:path in ['colorscheme '.a:name, l:switches[a:name.' '.a:background]]
    call s:Fresh(a:background)
    execute l:path
    let l:got = s:Groups()
    for [l:group, l:want] in items(a:groups)
      if get(l:got, l:group, {}) !=# l:want
        throw printf('%s %s (%s): %s is %s, upstream %s', a:name, a:background,
              \ l:path, l:group,
              \ string(get(l:got, l:group, {})), string(l:want))
      endif
    endfor
  endfor
endfunction

let s:headers = {
      \ 'gruvbox': ['" gruvbox, from morhetz/gruvbox bf2885a (MIT, Copyright (c) morhetz),',
      \   '" with g:gruvbox_improved_warnings, as Onesimus has always set it, and',
      \   '" the contrast refinements listed in scripts/build_themes.vim.'],
      \ 'nord': ['" Nord, from nordtheme/vim f13f5df (MIT, Copyright (c) 2016-present',
      \   '" Sven Greb), with the contrast refinements listed in',
      \   '" scripts/build_themes.vim.']}
let s:backgrounds = {'gruvbox': ['dark', 'light'], 'nord': ['dark']}

try
  for s:name in ['gruvbox', 'nord']
    execute 'set runtimepath^='.fnameescape(s:upstream[s:name])
  endfor
  let s:expected = {}
  for s:name in ['gruvbox', 'nord']
    let s:lines = s:headers[s:name] + [
          \ '" Generated by scripts/build_themes.vim; regenerate rather than edit.',
          \ '',
          \ '" A fresh Vim already holds the default groups, and the first :hi clear',
          \ '" in a MacVim session costs about 30 ms, so only a switch from another',
          \ '" scheme clears first.',
          \ 'if exists(''g:colors_name'')',
          \ '  hi clear',
          \ '  if exists(''g:syntax_on'') | syntax reset | endif',
          \ 'endif']
    if s:name ==# 'nord'
      " Nord is dark only; setting it here, with no g:colors_name yet, does not
      " reload a scheme.
      call add(s:lines, 'set background=dark')
    endif
    call add(s:lines, 'let g:colors_name = '''.s:name.'''')
    let s:expected[s:name] = {}
    let s:parts = []
    for s:bg in s:backgrounds[s:name]
      let [s:body, s:expected[s:name][s:bg]] = s:Body(s:name, s:bg)
      call add(s:parts, [s:bg, s:body])
    endfor
    if len(s:parts) == 1
      call extend(s:lines, s:parts[0][1])
    else
      call add(s:lines, 'if &background ==# ''light''')
      call extend(s:lines, map(copy(s:parts[1][1]), '"  ".v:val'))
      call add(s:lines, 'else')
      call extend(s:lines, map(copy(s:parts[0][1]), '"  ".v:val'))
      call add(s:lines, 'endif')
    endif
    call writefile(s:lines, s:root.'/'.s:name.'.vim')
  endfor
  " Check against the generated files only, never the upstream copies.
  for s:name in ['gruvbox', 'nord']
    execute 'set runtimepath-='.fnameescape(s:upstream[s:name])
  endfor
  execute 'set runtimepath^='.fnameescape(fnamemodify(s:root, ':h'))
  for s:name in ['gruvbox', 'nord']
    for [s:bg, s:groups] in items(s:expected[s:name])
      call s:Check(s:name, s:bg, s:groups)
    endfor
  endfor
  call writefile(['themes: generated and verified'], '/dev/stdout')
catch
  call writefile(['themes: '.v:exception], '/dev/stderr')
  cquit
endtry
qall!
