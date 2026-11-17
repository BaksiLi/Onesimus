" Shared writing policy. WebPreview.vim owns preview operations.

function! OnesimusPreviewHeadless() abort
  return webpreview#headless()
endfunction

function! OnesimusOpenExternal(target) abort
  return webpreview#external(a:target)
endfunction

function! OnesimusOpenBrowser(url) abort
  return webpreview#browser(a:url)
endfunction

function! OnesimusWritingPreview(...) abort
  if !s:RequireWritingBuffer() | return 0 | endif
  if &l:filetype ==# 'tex' && get(a:000, 0, 0)
    return OnesimusTexBuildAndView()
  endif
  return webpreview#open()
endfunction

function! OnesimusWritingPreviewStop() abort
  return webpreview#stop()
endfunction

function! OnesimusWritingSelect(text, line, ...) abort
  return call('webpreview#select', [a:text, a:line] + a:000)
endfunction

function! s:RequireWritingBuffer() abort
  if &l:buftype !=# ''
    call OnesimusNotify('WRITING ACTION UNAVAILABLE',
          \ ['Open a text, Markdown, TeX, Cogitatum, or bibliography source buffer.'], 1)
    return 0
  endif
  if !OnesimusIsWritingBuffer(bufnr('%'))
    call OnesimusNotify('WRITING ACTION UNAVAILABLE', [
          \ 'This buffer is not a writing filetype.',
          \ 'For a plain-text draft, use :setfiletype text.',
          \ ], 1)
    return 0
  endif
  return 1
endfunction

function! OnesimusWritingSave() abort
  if !s:RequireWritingBuffer()
    return 0
  endif
  if empty(bufname('%'))
    call OnesimusNotify('DRAFT NOT SAVED',
          \ ['Give this draft a filename with :saveas path/to/draft.txt.'], 1)
    return 0
  endif
  if &l:filetype ==# 'tex'
    return OnesimusTexSave()
  endif
  if !OnesimusSafeUpdate(1)
    return 0
  endif
  call OnesimusNotify('DRAFT SAVED',
        \ ['Saved '.fnamemodify(expand('%:p'), ':~:.').'.'], 0)
  return 1
endfunction

function! OnesimusWritingCountWords() abort
  if !s:RequireWritingBuffer()
    return 0
  endif
  if &l:filetype ==# 'tex'
    return OnesimusTexCountWords()
  endif
  if !exists('*wordcount')
    call OnesimusNotify('WORD COUNT UNAVAILABLE',
          \ ['This Vim lacks wordcount(); use g Ctrl-G for its native count.'], 1)
    return 0
  endif
  let l:count = wordcount()
  call OnesimusPopup('DRAFT WORD COUNT', [
        \ printf('  %d words · %d characters', l:count.words, l:count.chars),
        \ '  Current buffer only; unsaved edits are included.',
        \ '  Source count: markup is included; CJK word boundaries are approximate.',
        \ ])
  return 1
endfunction

function! s:RequireSpelling(...) abort
  if !s:RequireWritingBuffer()
    return 0
  endif
  if !has('spell')
    call OnesimusNotify('SPELLING UNAVAILABLE',
          \ ['Use a Vim build with +spell support.'], 1)
    return 0
  elseif get(a:000, 0, 1) && empty(&l:spelllang)
    call OnesimusNotify('CHOOSE A SPELLING LANGUAGE',
          \ ['Set :setlocal spelllang=en_us, or your preferred language.'], 1)
    return 0
  endif
  return 1
endfunction

function! OnesimusWritingToggleSpell() abort
  if !s:RequireSpelling(!&l:spell)
    return 0
  endif
  try
    setlocal spell!
  catch
    call OnesimusNotify('SPELLING UNAVAILABLE', [v:exception,
          \ 'Check :setlocal spelllang? and the installed Vim dictionaries.'], 1)
    return 0
  endtry
  call OnesimusNotify(&l:spell ? 'SPELLING ON' : 'SPELLING OFF', [
        \ 'Language: '.&l:spelllang.'. Source text is unchanged.',
        \ 'Use \\ → Spelling for the next word or suggestions.',
        \ ], 0)
  return 1
endfunction

function! s:SpellingAction(command) abort
  if !s:RequireSpelling()
    return 0
  endif
  try
    setlocal spell
    execute 'normal! '.a:command
  catch
    call OnesimusNotify('SPELLING UNAVAILABLE', [v:exception,
          \ 'Check :setlocal spelllang? and the installed Vim dictionaries.'], 1)
    return 0
  endtry
  return 1
endfunction

function! OnesimusWritingNextSpelling() abort
  return s:SpellingAction(']s')
endfunction

function! OnesimusWritingSuggest() abort
  if !s:RequireWritingBuffer()
    return 0
  endif
  let l:word = ''
  try
    let l:word = expand('<cword>')
  catch /E348:/
  endtry
  if empty(l:word)
    call OnesimusNotify('NO WORD SELECTED',
          \ ['Place the cursor on a word, then choose Spelling → Suggestions.'], 1)
    return 0
  endif
  return s:SpellingAction('z=')
endfunction

function! OnesimusWritingHelp() abort
  if &l:filetype ==# 'bib'
    call OnesimusPopup('BIBLIOGRAPHY GUIDE', [
          \ '  Save bibliography uses the same disk-conflict guard as TeX.',
          \ '  Check disk updates before continuing after collaborator edits.',
          \ '  Compare with disk shows both versions without overwriting either.',
          \ '  Preserve citation keys and generated-entry provenance.',
          \ '  Sentence reflow is for prose, not BibTeX records.',
          \ ])
    return 1
  endif
  call OnesimusPopup('WRITING GUIDE', [
        \ '  \\ opens actions for this draft.',
        \ '  F5 previews Markdown/Cogitatum drafts without saving.',
        \ '  TeX F5 saves and builds; PDF positions refer to that build.',
        \ '  \\v opens browser preview; \\s saves; \\o opens more tools.',
        \ '  Formulas render in place automatically; enter one to edit its source.',
        \ '  \\m switches automatic / raw formulas for this buffer.',
        \ '  Edit raw source here; browser preview has the complete typesetting.',
        \ '  Cogitatum terminal Reading follows saved files only.',
        \ '  Choose focus mode, word count, or Spelling from the writing menu.',
        \ '  Focus mode (\tw) changes the view, not the source.',
        \ '  Save is explicit. A word count or display toggle never saves.',
        \ '  ↳ marks a screen continuation; it is not a source newline.',
        \ '  Choose source breaks at meaningful sentences/clauses, not a width.',
        \ '  gq rewrites source; F6 uses the project formatter without saving.',
        \ '  Vim sentence motions: ) / (, and cis to change a sentence.',
        \ '  Spelling suggestions: choose a number; Enter alone cancels.',
        \ '  Native word counts include markup and approximate CJK words.',
        \ ])
  return 1
endfunction

command! OnesimusWritingSave call OnesimusWritingSave()
command! OnesimusWritingPreview call OnesimusWritingPreview()
command! OnesimusWritingPreviewStop call OnesimusWritingPreviewStop()
command! OnesimusWritingCountWords call OnesimusWritingCountWords()
command! OnesimusWritingToggleSpell call OnesimusWritingToggleSpell()
command! OnesimusWritingNextSpelling call OnesimusWritingNextSpelling()
command! OnesimusWritingSuggest call OnesimusWritingSuggest()
command! OnesimusWritingHelp call OnesimusWritingHelp()
