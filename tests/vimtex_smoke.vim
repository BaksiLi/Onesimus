" Real VimTeX v2.15 contract smoke test (no compiler process is started).
" Run with: vim -Nu tests/vimtex_smoke.vim -i NONE -n -es

let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let s:fixture = tempname().' vimtex project'
call mkdir(s:fixture, 'p')
" macOS exposes temporary files through both /var and /private/var.  Use one
" canonical spelling so VimTeX's path-keyed registry recognizes the main and
" magic-root child as siblings instead of creating equivalent duplicate ids.
let s:fixture = resolve(s:fixture)
let $XDG_STATE_HOME = s:fixture.'/state'
call writefile([
      \ '\documentclass{article}',
      \ '\begin{document}',
      \ '\input{child}',
      \ '\end{document}',
      \ ], s:fixture.'/main.tex')
call writefile(['% !TeX root = main.tex', 'Child.'],
      \ s:fixture.'/child.tex')
call writefile(['Extra.'], s:fixture.'/extra.tex')
call writefile(['\documentclass{article}', '\begin{document}',
      \ 'Another paper.', '\end{document}'], s:fixture.'/other.tex')

let $VIMRCDIR = s:root
let $MYVIMDOT = s:root.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

function! s:RunTests() abort
  try
    if !has_key(g:plugs, 'vimtex') || !isdirectory(g:plugs.vimtex.dir)
      call assert_report('the pinned VimTeX checkout is unavailable')
    else
      let l:installed_tag = system('git -C '.shellescape(g:plugs.vimtex.dir)
            \ .' describe --tags --exact-match HEAD 2>/dev/null')
      call assert_equal(0, v:shell_error,
            \ 'the installed VimTeX checkout must be an exact release tag')
      call assert_equal('v2.15', trim(l:installed_tag),
            \ 'the compatibility smoke test must exercise actual VimTeX v2.15')
    endif
    call assert_equal('v2.15', get(g:plugs.vimtex, 'tag', ''))
    call assert_false(has_key(g:plugs.vimtex, 'for'),
          \ 'external lazy loading would break global inverse search')
    call assert_equal(2, exists(':VimtexInverseSearch'),
          \ 'the global inverse-search command loads before a TeX buffer')

    execute 'edit '.fnameescape(s:fixture.'/main.tex')
    call assert_true(exists('b:vimtex'))
    let l:main_bufnr = bufnr('%')
    let l:initial_project_id = b:vimtex_id
    call assert_equal(resolve(fnamemodify(s:fixture.'/main.tex', ':p')),
          \ resolve(fnamemodify(b:vimtex.tex, ':p')))
    call assert_equal(2, exists(':VimtexCompileSS'))
    call assert_equal(2, exists(':VimtexCompile'))
    call assert_equal(0, exists(':VimtexView'))
    call assert_false(has_key(b:vimtex, 'viewer'), 'native viewer objects are unnecessary')
    call assert_equal(2, exists(':VimtexTocOpen'))
    call assert_equal(v:t_dict, type(b:vimtex.compiler))

    execute 'edit '.fnameescape(s:fixture.'/child.tex')
    let l:child_bufnr = bufnr('%')
    call assert_equal(l:initial_project_id, b:vimtex_id,
          \ 'main and magic-root child begin in one real VimTeX project')
    call assert_equal(resolve(fnamemodify(s:fixture.'/main.tex', ':p')),
          \ resolve(fnamemodify(b:vimtex.tex, ':p')),
          \ 'the real magic-root parser resolves a child to its main paper')

    " A local include/root/preamble edit invalidates VimTeX's cached project
    " graph.  Saving it reloads the project and must immediately rebind every
    " already-loaded sibling; v2.15 otherwise leaves the old id unregistered.
    call setline(2, '\input{extra}')
    call assert_true(OnesimusTeXStructureChanged(l:child_bufnr))
    call assert_true(OnesimusTexSave())
    call assert_false(getbufvar(l:child_bufnr, '&modified'))
    let l:reloaded_project_id = getbufvar(l:child_bufnr, 'vimtex_id', -1)
    call assert_true(vimtex#state#exists(l:reloaded_project_id),
          \ 'the current child must point at a registered reloaded state')
    call assert_equal(l:reloaded_project_id,
          \ getbufvar(l:main_bufnr, 'vimtex_id', -2),
          \ 'the loaded main buffer must be rebound to the reloaded project')
    call assert_true(vimtex#state#exists(
          \ getbufvar(l:main_bufnr, 'vimtex_id', -1)),
          \ "the main buffer must not retain VimTeX v2.15's removed id")
    call assert_true(getbufvar(l:main_bufnr, 'vimtex', {})
          \ is vimtex#state#get(l:reloaded_project_id),
          \ 'both buffers must share the live registry object after reload')
  finally
    call delete(s:fixture, 'rf')
  endtry
  if empty(v:errors)
    qall!
  endif
  for l:error in v:errors
    echomsg l:error
  endfor
  cquit
endfunction

augroup onesimus_vimtex_smoke
  autocmd!
  autocmd VimEnter * ++nested call <SID>RunTests()
augroup END
