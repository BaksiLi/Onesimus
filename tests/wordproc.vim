" Focus mode must be reversible and safe when lazy plugins are absent.
" Run with:
"   vim -Nu tests/wordproc.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

function! s:RunWordProcTests() abort
  let g:gitgutter_enabled = 0
  let l:number = &l:number
  let l:textwidth = &l:textwidth

  WPModeToggle
  call assert_false(empty(g:onesimus_wordproc_state))
  WPModeToggle
  call assert_equal({}, g:onesimus_wordproc_state)
  call assert_equal(0, g:gitgutter_enabled,
        \ 'focus mode preserves an already disabled GitGutter')
  call assert_equal(l:number, &l:number)
  call assert_equal(l:textwidth, &l:textwidth)

  if PlugInstalled('goyo.vim') && exists(':Goyo')
    silent Goyo
    call assert_true(exists('t:goyo_revert'))
    WPModeToggle
    call assert_true(exists('t:goyo_revert'),
          \ 'focus mode leaves a pre-existing Goyo session active')
    WPModeToggle
    call assert_true(exists('t:goyo_revert'),
          \ 'leaving focus mode does not close user-owned Goyo')
    silent! Goyo!
  endif

  if PlugInstalled('limelight.vim') && exists(':Limelight')
    silent Limelight
    call assert_true(exists('#limelight'))
    WPModeToggle
    call assert_true(exists('#limelight'),
          \ 'focus mode leaves a pre-existing Limelight session active')
    WPModeToggle
    call assert_true(exists('#limelight'),
          \ 'leaving focus mode does not close user-owned Limelight')
    silent! Limelight!
  endif

  let l:goyo_dir = g:plugs['goyo.vim'].dir
  let l:limelight_dir = g:plugs['limelight.vim'].dir
  let g:plugs['goyo.vim'].dir = '/tmp/onesimus-plugin-not-installed'
  let g:plugs['limelight.vim'].dir = '/tmp/onesimus-plugin-not-installed'
  let v:errmsg = ''
  WPModeToggle
  WPModeToggle
  call assert_notmatch('E492:', v:errmsg,
        \ 'missing focus plugins use the native fallback')
  let g:plugs['goyo.vim'].dir = l:goyo_dir
  let g:plugs['limelight.vim'].dir = l:limelight_dir

  call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors,
        \ '/tmp/onesimus-wordproc-result')
  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_wordproc_test
  autocmd!
  autocmd VimEnter * call <SID>RunWordProcTests()
augroup END
