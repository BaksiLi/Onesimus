" Project-aware Haskell formatter selection and health regression.
" Run with:
"   vim -Nu tests/ale_haskell.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

let s:fixture = tempname().' Haskell projects'
let s:all_tools = tempname().' Haskell tools'
let s:ormolu_only = tempname().' Ormolu only'
let s:no_tools = tempname().' no tools'
call mkdir(s:fixture, 'p')
call mkdir(s:all_tools, 'p')
call mkdir(s:ormolu_only, 'p')
call mkdir(s:no_tools, 'p')

function! s:FakeExecutable(directory, name) abort
  let l:path = a:directory.'/'.a:name
  call writefile(['#!/bin/sh', 'exit 0'], l:path)
  call setfperm(l:path, 'rwxr-xr-x')
endfunction

for s:tool in ['fourmolu', 'ormolu', 'stylish-haskell']
  call s:FakeExecutable(s:all_tools, s:tool)
endfor
call s:FakeExecutable(s:ormolu_only, 'ormolu')
unlet! s:tool

function! s:OpenProject(name, config, path) abort
  let l:root = s:fixture.'/'.a:name
  call mkdir(l:root.'/src', 'p')
  if !empty(a:config)
    call writefile(['# formatter policy'], l:root.'/'.a:config)
  endif
  let l:source = l:root.'/src/'.a:path
  call writefile(['module Fixture where', '', 'answer = 42'], l:source)
  execute 'edit! '.fnameescape(l:source)
  setfiletype haskell
  return l:root
endfunction

function! s:HealthText() abort
  OnesimusHealth
  let l:id = popup_list()[-1]
  let l:text = join(getbufline(winbufnr(l:id), 1, '$'), "\n")
  call popup_close(l:id)
  return l:text
endfunction

function! s:RunHaskellTests() abort
  try
    let $PATH = s:all_tools
    call s:OpenProject('fourmolu', 'fourmolu.yaml', 'Library.hs')
    call assert_equal('fourmolu', b:onesimus_haskell_formatter.fixer)
    call assert_equal('fourmolu.yaml',
          \ b:onesimus_haskell_formatter.configured)
    call assert_equal(['fourmolu', 'remove_trailing_lines',
          \ 'trim_whitespace'], b:ale_fixers)

    call s:OpenProject('ormolu', '.ormolu', 'Library.hs')
    call assert_equal('ormolu', b:onesimus_haskell_formatter.fixer)
    call assert_equal(['ormolu', 'remove_trailing_lines',
          \ 'trim_whitespace'], b:ale_fixers)

    call s:OpenProject('stylish', '.stylish-haskell.yaml', 'Library.hs')
    call assert_equal('stylish_haskell',
          \ b:onesimus_haskell_formatter.fixer)
    call assert_equal(['stylish_haskell', 'remove_trailing_lines',
          \ 'trim_whitespace'], b:ale_fixers)

    call s:OpenProject('default', '', 'Library.hs')
    call assert_equal('ormolu', b:onesimus_haskell_formatter.fixer,
          \ 'the unconfigured default agrees with HLS')

    " A project policy must fail visibly instead of producing a differently
    " formatted diff just because another formatter happens to be installed.
    let $PATH = s:ormolu_only
    call s:OpenProject('missing-fourmolu', 'fourmolu.yaml', 'Library.hs')
    call assert_false(b:onesimus_haskell_formatter.ready)
    call assert_equal('fourmolu', b:onesimus_haskell_formatter.fixer)
    call assert_equal(['remove_trailing_lines', 'trim_whitespace'],
          \ b:ale_fixers)
    let l:health = s:HealthText()
    call assert_match('missing\s\+format\s\+fourmolu', l:health)
    call assert_match('selected by fourmolu.yaml', l:health)
    call assert_match('F6\s\+tidy\s\+whitespace only', l:health)

    let $PATH = s:no_tools
    call s:OpenProject('missing-all', '', 'Library.hs')
    call assert_equal('', b:onesimus_haskell_formatter.fixer)
    call assert_equal(['remove_trailing_lines', 'trim_whitespace'],
          \ b:ale_fixers)
    let l:health = s:HealthText()
    call assert_match('missing\s\+server\s\+hls', l:health)
    call assert_match('install HLS with GHCup', l:health)
    call assert_match('missing\s\+format\s\+ormolu / fourmolu / stylish-haskell',
          \ l:health)

    setlocal filetype=text
    call assert_false(exists('b:ale_fixers'),
          \ 'dynamic Haskell fixers are released on a filetype change')

    call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors,
          \ '/tmp/onesimus-ale-haskell-result')
  finally
    call delete(s:fixture, 'rf')
    call delete(s:all_tools, 'rf')
    call delete(s:ormolu_only, 'rf')
    call delete(s:no_tools, 'rf')
  endtry

  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_ale_haskell_test
  autocmd!
  autocmd VimEnter * call <SID>RunHaskellTests()
augroup END
