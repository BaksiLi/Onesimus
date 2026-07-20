" Run with:
"   vim -Nu tests/compilerun.vim -i NONE -n -es

let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let s:fixture = tempname().' path with spaces $semi; quote'''
let s:bin = tempname()
call mkdir(s:fixture, 'p')
call mkdir(s:bin, 'p')

for s:program in [
      \ 'bash', 'python3', 'python', 'ruby', 'xdg-open', 'ghc', 'go', 'dot',
      \ 'gcc', 'g++', 'javac', 'java', 'rustc', 'tsc', 'node',
      \ ]
  let s:executable = s:bin.'/'.s:program
  call writefile(['#!/bin/sh', 'exit 0'], s:executable)
  call setfperm(s:executable, 'rwxr-xr-x')
endfor

let $PATH = s:bin
let g:asc_uname = 'linux'
let g:compilerun_timer = 0
let g:compilerun_calls = []

function! OnesimusCompilerunCapture(bang, options, command) abort
  call add(g:compilerun_calls, {
        \ 'bang': a:bang,
        \ 'options': deepcopy(a:options),
        \ 'command': a:command,
        \ })
  return 1
endfunction

let g:onesimus_compilerun_runner = 'OnesimusCompilerunCapture'
execute 'source '.fnameescape(s:root.'/functions/CompileRun.vim')

function! s:Run(filetype, filename, contents) abort
  let l:path = s:fixture.'/'.a:filename
  call writefile(a:contents, l:path)
  execute 'edit '.fnameescape(l:path)
  execute 'setlocal filetype='.a:filetype
  let g:compilerun_calls = []
  silent CompileRun
  call assert_equal(1, len(g:compilerun_calls),
        \ a:filetype.' should dispatch exactly one task')
  return [l:path, get(g:compilerun_calls, 0, {})]
endfunction

function! s:TestCompileChains() abort
  let [l:c, l:call] = s:Run('c', 'hello $x; it''s.c', ['int main(void) { return 0; }'])
  let l:binary = fnamemodify(l:c, ':r')
  let l:c_command = 'gcc -Wall -O2 '.shellescape(l:c).' -o '.shellescape(l:binary)
        \ .' && '.shellescape(l:binary)
  call assert_equal(l:c_command, l:call.command)
  call assert_equal({'cwd': s:fixture}, l:call.options)

  let [l:cpp, l:call] = s:Run('cpp', 'hello world.cpp', ['int main() {}'])
  let l:binary = fnamemodify(l:cpp, ':r')
  call assert_equal('g++ -Wall -O2 '.shellescape(l:cpp).' -o '.shellescape(l:binary)
        \ .' && '.shellescape(l:binary), l:call.command)

  let [l:rust, l:call] = s:Run('rust', 'hello world.rs', ['fn main() {}'])
  let l:binary = fnamemodify(l:rust, ':r')
  call assert_equal('rustc '.shellescape(l:rust).' -o '.shellescape(l:binary)
        \ .' && '.shellescape(l:binary), l:call.command)

  let [l:typescript, l:call] = s:Run('typescript', 'hello world.ts', ['let n = 1'])
  call assert_equal('tsc '.shellescape(l:typescript).' && node '
        \ .shellescape(fnamemodify(l:typescript, ':r').'.js'), l:call.command)
endfunction

function! s:TestJavaUsesFilenameAsClass() abort
  let [l:java, l:call] = s:Run('java', 'HelloWorld.java',
        \ ['class HelloWorld { public static void main(String[] args) {} }'])
  call assert_equal('javac '.shellescape(l:java).' && java -cp '
        \ .shellescape(s:fixture).' '.shellescape('HelloWorld'), l:call.command)
  call assert_equal({'cwd': s:fixture}, l:call.options)
endfunction

function! s:TestGraphvizIsAtomic() abort
  let [l:dot, l:call] = s:Run('dot', 'diagram $x.dot', ['digraph { a -> b }'])
  let l:image = fnamemodify(l:dot, ':r').'.png'
  call assert_equal('dot -Tpng '.shellescape(l:dot).' -o '.shellescape(l:image)
        \ .' && xdg-open '.shellescape(l:image), l:call.command)
  call assert_equal(1, count(l:call.command, '&&'))
endfunction

function! s:TestInterpreterAndTimer() abort
  let [l:python, l:call] = s:Run('python', 'hello world.py', ['print("hello")'])
  call assert_equal('python3 '.shellescape(l:python), l:call.command)
  call assert_equal({'cwd': s:fixture, 'raw': 1}, l:call.options)

  let g:compilerun_timer = 1
  let [l:c, l:call] = s:Run('c', 'timed program.c', ['int main(void) { return 0; }'])
  let l:binary = fnamemodify(l:c, ':r')
  let l:chain = 'gcc -Wall -O2 '.shellescape(l:c).' -o '.shellescape(l:binary)
        \ .' && '.shellescape(l:binary)
  call assert_equal('time sh -c '.shellescape(l:chain), l:call.command)
  let g:compilerun_timer = 0
endfunction

function! s:TestFailuresDoNotDispatch() abort
  enew
  setlocal filetype=python
  let g:compilerun_calls = []
  let l:message = ''
  redir => l:message
  CompileRun
  redir END
  call assert_equal([], g:compilerun_calls)
  call assert_match('save this buffer before running it', l:message)

  execute 'edit '.fnameescape(s:fixture.'/notes.txt')
  call setline(1, 'plain text')
  setlocal filetype=text
  let g:compilerun_calls = []
  let l:message = ''
  redir => l:message
  CompileRun
  redir END
  call assert_equal([], g:compilerun_calls)
  call assert_match('cannot run filetype text', l:message)

  let l:source = s:fixture.'/missing compiler.c'
  call writefile(['int main(void) { return 0; }'], l:source)
  execute 'edit! '.fnameescape(l:source)
  setlocal filetype=c
  call delete(s:bin.'/gcc')
  let g:compilerun_calls = []
  let l:message = ''
  redir => l:message
  CompileRun
  redir END
  call assert_equal([], g:compilerun_calls)
  call assert_match('gcc is required', l:message)
endfunction

function! s:RunTests() abort
  try
    call s:TestCompileChains()
    call s:TestJavaUsesFilenameAsClass()
    call s:TestGraphvizIsAtomic()
    call s:TestInterpreterAndTimer()
    call s:TestFailuresDoNotDispatch()
  finally
    call delete(s:fixture, 'rf')
    call delete(s:bin, 'rf')
  endtry

  if empty(v:errors)
    qall!
  endif
  for l:error in v:errors
    echomsg l:error
  endfor
  cquit
endfunction

augroup onesimus_compilerun_test
  autocmd!
  autocmd VimEnter * call <SID>RunTests()
augroup END
