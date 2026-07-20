" ALE owns the complete language-tooling pipeline in Onesimus:
" LSP, diagnostics, CLI linting, completion, and formatting.

let g:ale_linters_explicit = 1
let g:ale_lint_delay = 300
let g:ale_lint_on_text_changed = 'normal'
let g:ale_lint_on_insert_leave = 1
let g:ale_lint_on_save = 1

let g:ale_sign_column_always = 1
let g:ale_echo_cursor = 1
let g:ale_hover_to_floating_preview = 1
let g:ale_floating_preview = 1

" ALE's completion remains Vim-native.  UltiSnips keeps its independent
" <C-e> expansion path, so completion and personal snippets do not compete.
let g:ale_completion_enabled = 1
let g:ale_completion_delay = 120
let g:ale_completion_max_suggestions = 50
set completeopt=menu,menuone,noselect,noinsert
if has('patch-8.1.1880')
  set completeopt+=popup
endif

function! s:LinterAvailable(filetype, name) abort
  return !empty(globpath(&runtimepath,
        \ 'ale_linters/'.a:filetype.'/'.a:name.'.vim'))
endfunction

function! s:FixerAvailable(name) abort
  return !empty(globpath(&runtimepath,
        \ 'autoload/ale/fixers/'.a:name.'.vim'))
endfunction

" Preserve the language server installed by the previous vim-lsp-settings
" setup when it exists.  Fresh installations simply discover pylsp in PATH or
" in the active project environment through ALE.
let s:legacy_pylsp = fnamemodify(
      \ '~/.local/share/vim-lsp-settings/servers/pylsp-all/venv/bin/pylsp',
      \ ':p')
if !executable('pylsp') && executable(s:legacy_pylsp)
  let g:ale_python_pylsp_executable = s:legacy_pylsp
endif

" pylsp supplies navigation, hover, rename, and completion.  Ruff is the one
" source for Python style diagnostics, so disable overlapping pylsp plugins.
let g:ale_python_pylsp_config = {
      \ 'pylsp': {
      \   'plugins': {
      \     'autopep8': {'enabled': v:false},
      \     'flake8': {'enabled': v:false},
      \     'mccabe': {'enabled': v:false},
      \     'pycodestyle': {'enabled': v:false},
      \     'pydocstyle': {'enabled': v:false},
      \     'pyflakes': {'enabled': v:false},
      \     'pylint': {'enabled': v:false},
      \     'yapf': {'enabled': v:false},
      \   },
      \ },
      \ }

let s:markdown_linters = ['markdownlint']
if s:LinterAvailable('markdown', 'marksman')
  call insert(s:markdown_linters, 'marksman')
endif

" One semantic server plus, where useful, one style checker per language.
" ALE silently skips tools which are not installed, including project-local
" Node executables which it discovers on demand.
let g:ale_linters = {
      \ 'c': ['clangd'],
      \ 'cpp': ['clangd'],
      \ 'go': ['gopls'],
      \ 'haskell': ['hls'],
      \ 'javascript': ['tsserver', 'eslint'],
      \ 'javascriptreact': ['tsserver', 'eslint'],
      \ 'json': ['vscodejson'],
      \ 'markdown': s:markdown_linters,
      \ 'python': ['pylsp', 'ruff'],
      \ 'rust': ['analyzer'],
      \ 'sh': ['language_server', 'shellcheck'],
      \ 'tex': ['chktex'],
      \ 'typescript': ['tsserver', 'eslint'],
      \ 'typescriptreact': ['tsserver', 'eslint'],
      \ 'vim': ['vimls', 'vint'],
      \ 'yaml': ['yaml-language-server', 'yamllint'],
      \ }

let s:clean_text = ['remove_trailing_lines', 'trim_whitespace']
let s:haskell_formatters = [
      \ {'fixer': 'fourmolu', 'executable': 'fourmolu',
      \   'configs': ['fourmolu.yaml', '.fourmolu.yaml']},
      \ {'fixer': 'ormolu', 'executable': 'ormolu',
      \   'configs': ['.ormolu']},
      \ {'fixer': 'stylish_haskell', 'executable': 'stylish-haskell',
      \   'configs': ['.stylish-haskell.yaml']},
      \ ]

function! s:PythonToolAvailable(buffer, name) abort
  try
    let l:virtualenv = ale#python#FindVirtualenv(a:buffer)
  catch
    let l:virtualenv = $VIRTUAL_ENV
  endtry

  if !empty(l:virtualenv)
    let l:bin = has('win32') ? 'Scripts' : 'bin'
    if executable(l:virtualenv.'/'.l:bin.'/'.a:name)
      return 1
    endif
  endif

  return executable(a:name)
endfunction

" Prefer Ruff's paired fix/format pipeline, but retain the user's older
" isort/Black workflow when Ruff is absent.  This is buffer-local because ALE
" can discover a different virtualenv for each project.
function! s:ConfigurePythonFixers() abort
  let l:fixers = []
  let l:ruff_supported = s:LinterAvailable('python', 'ruff')
        \ && !empty(globpath(&runtimepath,
        \ 'autoload/ale/fixers/ruff_format.vim'))

  if l:ruff_supported && s:PythonToolAvailable(bufnr(''), 'ruff')
    let l:fixers = ['ruff', 'ruff_format']
  else
    if s:PythonToolAvailable(bufnr(''), 'isort')
      call add(l:fixers, 'isort')
    endif
    if s:PythonToolAvailable(bufnr(''), 'black')
      call add(l:fixers, 'black')
    endif
  endif

  let b:ale_fixers = l:fixers + s:clean_text
endfunction

function! s:HaskellFormatter(buffer) abort
  let l:name = bufname(a:buffer)
  let l:directory = empty(l:name)
        \ ? getcwd()
        \ : fnamemodify(l:name, ':p:h')

  " A checked-in formatter config is a project contract.  If its executable
  " is absent, do not silently apply a different style and create a noisy diff.
  while !empty(l:directory)
    for l:formatter in s:haskell_formatters
      for l:config in l:formatter.configs
        if filereadable(l:directory.'/'.l:config)
          return extend(copy(l:formatter), {
                \ 'configured': l:config,
                \ 'ready': s:FixerAvailable(l:formatter.fixer)
                \   && executable(l:formatter.executable),
                \ })
        endif
      endfor
    endfor

    let l:parent = fnamemodify(l:directory, ':h')
    if l:parent ==# l:directory
      break
    endif
    let l:directory = l:parent
  endwhile

  " With no project policy, follow HLS's default first, then the configurable
  " Fourmolu fork, then the deliberately narrower import organiser.
  for l:name in ['ormolu', 'fourmolu', 'stylish_haskell']
    for l:formatter in s:haskell_formatters
      if l:formatter.fixer ==# l:name
            \ && s:FixerAvailable(l:formatter.fixer)
            \ && executable(l:formatter.executable)
        return extend(copy(l:formatter), {'configured': '', 'ready': 1})
      endif
    endfor
  endfor

  return {'fixer': '', 'executable': '', 'configured': '', 'ready': 0}
endfunction

function! s:ConfigureHaskellFixers() abort
  let b:onesimus_haskell_formatter = s:HaskellFormatter(bufnr(''))
  let l:fixers = b:onesimus_haskell_formatter.ready
        \ ? [b:onesimus_haskell_formatter.fixer]
        \ : []
  let b:ale_fixers = l:fixers + s:clean_text
endfunction

function! s:ResetLanguageFixers() abort
  if exists('b:onesimus_language_fixers')
    unlet! b:ale_fixers b:onesimus_language_fixers
          \ b:onesimus_haskell_formatter
  endif
endfunction

function! s:RefreshLanguageFixers() abort
  call s:ResetLanguageFixers()
  if &l:filetype ==# 'python'
    call s:ConfigurePythonFixers()
    let b:onesimus_language_fixers = 'python'
  elseif &l:filetype ==# 'haskell'
    call s:ConfigureHaskellFixers()
    let b:onesimus_language_fixers = 'haskell'
  endif
endfunction

augroup onesimus_ale_language_fixers
  autocmd!
  autocmd FileType * call <SID>RefreshLanguageFixers()
  autocmd BufEnter *.py,*.hs,*.lhs call <SID>RefreshLanguageFixers()
augroup END

" F6 remains the single formatting gesture.  Fixing on save stays off so an
" upgrade never rewrites a file merely because it was opened and saved.
let g:ale_fix_on_save = 0
let g:ale_fixers = {
      \ '*': s:clean_text,
      \ 'c': ['clangformat'] + s:clean_text,
      \ 'cpp': ['clangformat'] + s:clean_text,
      \ 'go': ['gofmt'] + s:clean_text,
      \ 'haskell': s:clean_text,
      \ 'javascript': ['eslint', 'prettier'] + s:clean_text,
      \ 'javascriptreact': ['eslint', 'prettier'] + s:clean_text,
      \ 'json': ['prettier'] + s:clean_text,
      \ 'markdown': ['prettier'] + s:clean_text,
      \ 'python': s:clean_text,
      \ 'rust': ['rustfmt'] + s:clean_text,
      \ 'sh': ['shfmt'] + s:clean_text,
      \ 'tex': ['latexindent'] + s:clean_text,
      \ 'typescript': ['eslint', 'prettier'] + s:clean_text,
      \ 'typescriptreact': ['eslint', 'prettier'] + s:clean_text,
      \ 'yaml': ['prettier'] + s:clean_text,
      \ }

" Semantic mappings appear only after an LSP server has actually connected.
" Treat them as a reversible buffer lease: FileType changes can invalidate an
" ALE connection, and a user's mapping made while the lease is active must win
" over our eventual cleanup.
function! s:MapLSPAction(lhs, plug, action) abort
  if !exists('b:onesimus_lsp_mappings')
    let b:onesimus_lsp_mappings = {}
  endif
  if has_key(b:onesimus_lsp_mappings, a:lhs)
    return
  endif

  let l:original = maparg(a:lhs, 'n', 0, 1)
  if !get(l:original, 'buffer', 0)
    " Removing our buffer-local map will reveal a global map automatically.
    let l:original = {}
  endif
  execute 'nmap <silent><buffer> '.a:lhs
        \ .' :<C-U>call OnesimusTrack('.string(a:action).')<CR>'.a:plug
  let b:onesimus_lsp_mappings[a:lhs] = {
        \ 'installed': maparg(a:lhs, 'n', 0, 1),
        \ 'original': l:original,
        \ }
endfunction

function! s:RestoreLSPMapping(lhs, lease) abort
  " Do not undo an explicit mapping (or unmapping) made after LSP startup.
  if maparg(a:lhs, 'n', 0, 1) !=# get(a:lease, 'installed', {})
    return
  endif

  execute 'silent! nunmap <buffer> '.a:lhs
  let l:original = get(a:lease, 'original', {})
  if !empty(l:original)
    if exists('*mapset')
      call mapset('n', 0, l:original)
    else
      " mapset() is available in supported Vim releases.  On an unusually
      " old 8.2 patchset, exposing the global/native mapping is safer than a
      " lossy reconstruction of an <expr> or <script> user mapping.
      echohl WarningMsg
      echomsg 'Onesimus could not restore a buffer mapping: mapset() is unavailable.'
      echohl None
    endif
  endif
endfunction

function! s:TeardownLSPBuffer() abort
  for [l:lhs, l:lease] in items(get(b:, 'onesimus_lsp_mappings', {}))
    call s:RestoreLSPMapping(l:lhs, l:lease)
  endfor

  if exists('b:onesimus_lsp_omnifunc_before')
        \ && &l:omnifunc ==# 'ale#completion#OmniFunc'
    let &l:omnifunc = b:onesimus_lsp_omnifunc_before
  endif
  unlet! b:onesimus_lsp_mappings b:onesimus_lsp_omnifunc_before
        \ b:onesimus_lsp_ready
endfunction

function! s:RefreshLSPBuffer() abort
  if !get(b:, 'onesimus_lsp_ready', 0)
    return
  endif
  try
    let l:enabled = ale#lsp_linter#GetEnabled(bufnr(''))
  catch /^Vim\%((\a\+)\)\=:E117:/
    let l:enabled = []
  endtry
  if empty(l:enabled)
    call s:TeardownLSPBuffer()
  endif
endfunction

function! s:ConfigureLSPBuffer() abort
  if !exists('b:onesimus_lsp_omnifunc_before')
    let b:onesimus_lsp_omnifunc_before = &l:omnifunc
  endif
  setlocal omnifunc=ale#completion#OmniFunc
  let b:onesimus_lsp_ready = 1
  for l:action in ['code.definition', 'code.references',
        \ 'code.implementation', 'code.type_definition', 'code.hover',
        \ 'code.rename', 'code.action']
    call OnesimusOffer(l:action)
  endfor
  if get(g:, 'onesimus_usage_enabled', 1)
        \ && exists('*OnesimusWorkspaceSymbolsAvailable')
        \ && OnesimusWorkspaceSymbolsAvailable()
    call OnesimusOffer('nav.workspace_symbols')
  endif
  call s:MapLSPAction('gd', '<Plug>(ale_go_to_definition)', 'code.definition')
  call s:MapLSPAction('gr', '<Plug>(ale_find_references)', 'code.references')
  call s:MapLSPAction('K', '<Plug>(ale_hover)', 'code.hover')
  call s:MapLSPAction('<leader>rn', '<Plug>(ale_rename)', 'code.rename')
  call s:MapLSPAction('<leader>ca', '<Plug>(ale_code_action)', 'code.action')
endfunction

augroup onesimus_ale_lsp
  autocmd!
  autocmd FileType * call <SID>TeardownLSPBuffer()
  autocmd User ALELSPStarted call <SID>ConfigureLSPBuffer()
  " ALE has no stopped event today.  Its lint lifecycle still lets us remove
  " stale affordances when LSP is disabled or the new filetype has no server.
  autocmd User ALELintPre call <SID>RefreshLSPBuffer()
augroup END

" Keep the old [a/]a muscle memory and teach the conventional [d/]d aliases.
nmap <silent> [a <Plug>(ale_previous_wrap)
nmap <silent> ]a <Plug>(ale_next_wrap)
nmap <silent> [d <Plug>(ale_previous_wrap)
nmap <silent> ]d <Plug>(ale_next_wrap)

function! s:OpenDiagnostics() abort
  if exists(':ALEPopulateLocList')
    call OnesimusTrack('code.diagnostics')
    ALEPopulateLocList
    lopen
    return
  endif

  echohl WarningMsg
  echomsg 'Diagnostics need ALE; run :PlugInstall ale.'
  echohl None
endfunction

function! s:LanguageInfo() abort
  if exists(':ALEInfo')
    ALEInfo
    return
  endif

  echohl WarningMsg
  echomsg 'Language-tool details need ALE; run :PlugInstall ale.'
  echohl None
endfunction

function! s:Format() abort
  if exists(':ALEFix')
    " Pick up a formatter installed, removed, or configured since this buffer
    " was entered.  Explicit F6 is the natural refresh boundary.
    call s:RefreshLanguageFixers()
    call OnesimusTrack('code.format')
    ALEFix
    return
  endif

  echohl WarningMsg
  echomsg 'Formatting needs ALE; run :PlugInstall ale.'
  echohl None
endfunction

function! s:RenameSymbol() abort
  if get(b:, 'onesimus_lsp_ready', 0) && exists(':ALERename')
    call OnesimusTrack('code.rename')
    ALERename
    return
  endif
  echohl WarningMsg
  echomsg 'Symbol rename needs ALE and an active language server.'
  echohl None
endfunction

function! s:CodeAction() abort
  if get(b:, 'onesimus_lsp_ready', 0) && exists(':ALECodeAction')
    call OnesimusTrack('code.action')
    ALECodeAction
    return
  endif
  echohl WarningMsg
  echomsg 'Code actions need ALE and an active language server.'
  echohl None
endfunction

" Less common navigation lives in the contextual guide instead of taking
" Vim's native gi (last insert) and gt (next tab).  Keep one internal entry
" point so the guide can validate readiness and record use consistently.
let s:lsp_navigation = {
      \ 'definition': ['ALEGoToDefinition', 'code.definition'],
      \ 'references': ['ALEFindReferences', 'code.references'],
      \ 'implementation': ['ALEGoToImplementation', 'code.implementation'],
      \ 'type_definition': ['ALEGoToTypeDefinition', 'code.type_definition'],
      \ }

function! OnesimusLSPNavigate(target) abort
  let l:action = get(s:lsp_navigation, a:target, [])
  if empty(l:action)
    echohl WarningMsg
    echomsg 'Unknown language navigation target: '.a:target
    echohl None
    return 0
  endif
  if !get(b:, 'onesimus_lsp_ready', 0)
        \ || !exists(':'.l:action[0])
    echohl WarningMsg
    echomsg 'Symbol navigation needs ALE and an active language server.'
    echohl None
    return 0
  endif

  call OnesimusTrack(l:action[1])
  execute l:action[0]
  return 1
endfunction

command! OnesimusDiagnostics call <SID>OpenDiagnostics()
command! OnesimusLanguageInfo call <SID>LanguageInfo()
command! OnesimusFormat call <SID>Format()
command! OnesimusRenameSymbol call <SID>RenameSymbol()
command! OnesimusCodeAction call <SID>CodeAction()
nnoremap <silent> <leader>ld :OnesimusDiagnostics<CR>
nnoremap <silent> <leader>li :OnesimusHealth<CR>

function! s:ConfiguredFixers() abort
  if exists('b:ale_fixers') && type(b:ale_fixers) is v:t_list
    let l:fixers = b:ale_fixers
  else
    let l:fixers = get(g:ale_fixers, &filetype,
          \ get(g:ale_fixers, '*', []))
  endif

  return filter(copy(l:fixers), 'type(v:val) is v:t_string')
endfunction

function! s:JiebaHealthLine() abort
  if exists('*OnesimusJiebaReady') && OnesimusJiebaReady()
    return 'ready    words    jieba.vim (ASCII-compatible)'
  elseif !empty(get(g:, 'onesimus_jieba_error', ''))
    return 'failed   words    '.g:onesimus_jieba_error
  elseif index(get(g:, 'onesimus_prose_filetypes', []), &filetype) < 0
    " A cold backend is prose guidance; an active or failed backend is useful
    " status in every filetype because loading is content-driven by default.
    return ''
  elseif !has('python3')
    return 'native   words    jieba.vim needs +python3'
  elseif !has_key(get(g:, 'plugs', {}), 'jieba.vim')
        \ || !isdirectory(get(g:plugs['jieba.vim'], 'dir', ''))
    return 'native   words    run :PlugInstall jieba.vim'
  elseif !exists('g:loaded_jieba_vim')
    return 'lazy     words    activates when Han text appears'
  endif
  return 'native   words    run :OnesimusJiebaInstall'
endfunction

function! s:HaskellFormatterHealthLine() abort
  if &l:filetype !=# 'haskell'
    return ''
  endif
  let l:formatter = get(b:, 'onesimus_haskell_formatter', {})
  if get(l:formatter, 'ready', 0)
    return ''
  elseif !empty(get(l:formatter, 'configured', ''))
    return 'missing  format   '.l:formatter.executable
          \ .' · selected by '.l:formatter.configured
  endif
  return 'missing  format   ormolu / fourmolu / stylish-haskell'
endfunction

function! s:HealthLines() abort
  let l:filetype = &filetype ==# '' ? '[no filetype]' : &filetype
  let l:lines = ['Filetype  '.l:filetype, '']
  let l:haskell_hls_missing = 0
  if !exists(':ALEInfo')
    call add(l:lines, 'missing  tools    ALE · run :PlugInstall ale')
  else
    try
      let l:linters = ale#linter#Get(&filetype)
      if empty(l:linters)
        call add(l:lines, 'native   tools    no language tools configured')
      endif
      for l:linter in l:linters
        let l:executable = ale#linter#GetExecutable(bufnr(''), l:linter)
        let l:role = empty(get(l:linter, 'lsp', '')) ? 'lint' : 'server'
        let l:status = executable(l:executable) ? 'ready  ' : 'missing'
        call add(l:lines, printf('%s %-7s %-20s %s', l:status, l:role,
              \ l:linter.name, l:executable))
        if &l:filetype ==# 'haskell' && l:linter.name ==# 'hls'
              \ && l:status ==# 'missing'
          let l:haskell_hls_missing = 1
        endif
      endfor
    catch
      call add(l:lines, 'failed   inspect  '.v:exception)
    endtry

    let l:fixers = s:ConfiguredFixers()
    let l:formatters = filter(copy(l:fixers),
          \ 'index(s:clean_text, v:val) < 0')
    if !empty(l:formatters)
      call extend(l:lines, ['', 'F6       format   '.join(l:formatters, ', ')])
    elseif !empty(l:fixers)
      call extend(l:lines, ['', 'F6       tidy     whitespace only'])
    endif
    let l:haskell_formatter = s:HaskellFormatterHealthLine()
    if !empty(l:haskell_formatter)
      call add(l:lines, l:haskell_formatter)
    endif
    if l:haskell_hls_missing
      call add(l:lines, 'hint     inspect  install HLS with GHCup')
    endif
    call add(l:lines, 'Details            :ALEInfo')
  endif

  let l:jieba = s:JiebaHealthLine()
  if !empty(l:jieba)
    call extend(l:lines, ['', l:jieba])
  endif
  return l:lines
endfunction

function! s:OnesimusHealth() abort
  " Health is a live inspection, not a snapshot from the last FileType event.
  call s:RefreshLanguageFixers()
  call OnesimusTrack('code.health')
  let l:lines = s:HealthLines()
  if exists('*OnesimusPopup')
    call OnesimusPopup('TOOL STATUS', l:lines)
  else
    for l:line in l:lines
      echomsg l:line
    endfor
  endif
endfunction
command! OnesimusHealth call <SID>OnesimusHealth()

call s:RefreshLanguageFixers()
