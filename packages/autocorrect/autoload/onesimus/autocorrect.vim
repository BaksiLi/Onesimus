" AutoCorrect (huacnlee/autocorrect) checks spacing and punctuation between
" CJK and Latin text, following the Chinese copywriting conventions of
" W3C clreq. ALE runs it as a linter and, through F6, as a fixer.

call ale#Set('autocorrect_executable', 'autocorrect')

let s:types = {'tex': 'tex', 'markdown': 'md', 'text': 'txt'}
let s:config = expand('<sfile>:p:h:h:h').'/autocorrectrc'

" A project's .autocorrectrc is its contract; otherwise use ours, which only
" leaves code blocks alone.
function! s:Options(buffer) abort
  let l:config = ale#path#FindNearestFile(a:buffer, '.autocorrectrc')
  return ' -c '.ale#Escape(empty(l:config) ? s:config : l:config)
        \ .' --stdin --type '.get(s:types, getbufvar(a:buffer, '&filetype'), 'txt')
endfunction

function! onesimus#autocorrect#Command(buffer) abort
  return '%e --lint --format json'.s:Options(a:buffer)
endfunction

" AutoCorrect reports the whole corrected line, so the message shows it.
function! onesimus#autocorrect#Handle(buffer, lines) abort
  let l:output = []
  for l:file in get(json_decode(join(a:lines, '')), 'messages', [])
    for l:line in l:file.lines
      call add(l:output, {'lnum': l:line.l, 'col': l:line.c, 'type': 'W',
            \ 'sub_type': 'style', 'text': 'CJK spacing: '.trim(l:line.new)})
    endfor
  endfor
  return l:output
endfunction

function! onesimus#autocorrect#Fix(buffer) abort
  return {'command': ale#Escape(ale#Var(a:buffer, 'autocorrect_executable'))
        \ .s:Options(a:buffer)}
endfunction

function! onesimus#autocorrect#Define(filetype) abort
  call ale#linter#Define(a:filetype, {
        \ 'name': 'autocorrect',
        \ 'executable': {buffer -> ale#Var(buffer, 'autocorrect_executable')},
        \ 'command': function('onesimus#autocorrect#Command'),
        \ 'callback': 'onesimus#autocorrect#Handle',
        \ })
endfunction
