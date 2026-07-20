" Stable Onesimus actions.  Mappings point here instead of at plugins so the
" implementation can evolve without changing muscle memory.

function! s:Track(action) abort
  if exists('*OnesimusTrack')
    call OnesimusTrack(a:action)
  endif
endfunction

function! s:OpenHome(track) abort
  if !exists(':Startify')
    echohl WarningMsg
    echomsg 'Onesimus Home needs vim-startify; run :PlugInstall vim-startify.'
    echohl None
    return
  endif
  if a:track
    call s:Track('meta.home')
  endif
  silent Startify
endfunction

function! OnesimusMaybeHome() abort
  if get(g:, 'onesimus_bootstrap_pending', 0)
        \ || !get(g:, 'onesimus_home_enabled', 1) || argc() != 0
        \ || line2byte('$') != -1 || &modified || !empty(bufname())
        \ || &buftype !=# '' || winnr('$') != 1 || tabpagenr('$') != 1
        \ || !empty(get(v:, 'this_session', ''))
    return
  endif
  call s:OpenHome(0)
endfunction

function! s:MaybeHomeTimer(timer) abort
  call OnesimusMaybeHome()
endfunction

function! s:ScheduleHome() abort
  if exists('*timer_start')
    call timer_start(0, function('<SID>MaybeHomeTimer'))
  else
    call OnesimusMaybeHome()
  endif
endfunction

function! s:OpenHelp() abort
  let l:help = $VIMRCDIR.'/README.md'
  if !filereadable(l:help)
    echohl ErrorMsg
    echomsg 'Onesimus documentation not found: '.l:help
    echohl None
    return
  endif
  call s:Track('meta.help')
  execute 'view '.fnameescape(l:help)
endfunction

function! s:EditConfig() abort
  call s:Track('meta.config')
  execute 'vsplit '.fnameescape($MYVIMDOT)
endfunction

" Updating replaces files on disk while this Vim keeps executing the version
" already in memory.  The global state survives an intentional :source during
" a running job, so a reload cannot accidentally start a second git process.
if !exists('g:onesimus_update_state')
      \ || type(g:onesimus_update_state) isnot v:t_dict
  let g:onesimus_update_state = {'running': 0, 'generation': 0}
else
  let g:onesimus_update_state.running =
        \ get(g:onesimus_update_state, 'running', 0)
  let g:onesimus_update_state.generation =
        \ get(g:onesimus_update_state, 'generation', 0)
endif

function! s:ShowUpdateResult(lines, failed) abort
  if exists('*OnesimusNotify')
    call OnesimusNotify('ONESIMUS / UPDATE', a:lines, a:failed)
    return
  endif
  if exists('*OnesimusPopupSupported') && OnesimusPopupSupported()
        \ && exists('*OnesimusPopup')
    call OnesimusPopup('ONESIMUS / UPDATE', a:lines)
    return
  endif

  redraw
  if a:failed
    echohl ErrorMsg
  else
    echohl MoreMsg
  endif
  echomsg 'Onesimus update'
  echohl None
  for l:line in a:lines
    echomsg l:line
  endfor
endfunction

function! s:UpdateFailureLines(state) abort
  let l:status = get(a:state, 'exit_status', -1)
  let l:lines = [l:status >= 0
        \ ? printf('Update failed (exit %d).', l:status)
        \ : 'The update process could not be started.']
  if !empty(get(a:state, 'stdout', []))
    call extend(l:lines, ['', 'Output:'] + a:state.stdout)
  endif
  if !empty(get(a:state, 'stderr', []))
    call extend(l:lines, ['', 'Errors:'] + a:state.stderr)
  endif
  if empty(get(a:state, 'stdout', []))
        \ && empty(get(a:state, 'stderr', []))
    call extend(l:lines, ['', 'No diagnostic output was produced.'])
  endif
  call extend(l:lines, ['',
        \ 'Nothing was reloaded. Fix the issue, then run :OnesimusUpdate again.'])
  return l:lines
endfunction

function! s:FinishUpdate(generation) abort
  if get(g:onesimus_update_state, 'generation', -1) != a:generation
        \ || !get(g:onesimus_update_state, 'running', 0)
    return
  endif
  let g:onesimus_update_state.running = 0
  if get(g:onesimus_update_state, 'exit_status', -1) == 0
    call s:ShowUpdateResult([
          \ 'Update completed.',
          \ '',
          \ 'Restart Vim to use the updated configuration.',
          \ ], 0)
  else
    call s:ShowUpdateResult(
          \ s:UpdateFailureLines(g:onesimus_update_state), 1)
  endif
endfunction

function! s:MaybeFinishUpdate(generation) abort
  if get(g:onesimus_update_state, 'generation', -1) == a:generation
        \ && get(g:onesimus_update_state, 'exited', 0)
        \ && get(g:onesimus_update_state, 'closed', 0)
    call s:FinishUpdate(a:generation)
  endif
endfunction

function! s:UpdateOutput(generation, stream, channel, message) abort
  if get(g:onesimus_update_state, 'generation', -1) != a:generation
        \ || !get(g:onesimus_update_state, 'running', 0)
    return
  endif
  let l:message = substitute(a:message, '\r$', '', '')
  call add(g:onesimus_update_state[a:stream], l:message)
endfunction

function! s:UpdateExited(generation, job, status) abort
  if get(g:onesimus_update_state, 'generation', -1) != a:generation
        \ || !get(g:onesimus_update_state, 'running', 0)
    return
  endif
  let g:onesimus_update_state.exit_status = a:status
  let g:onesimus_update_state.exited = 1
  call s:MaybeFinishUpdate(a:generation)
endfunction

function! s:UpdateClosed(generation, channel) abort
  if get(g:onesimus_update_state, 'generation', -1) != a:generation
        \ || !get(g:onesimus_update_state, 'running', 0)
    return
  endif
  let g:onesimus_update_state.closed = 1
  call s:MaybeFinishUpdate(a:generation)
endfunction

function! s:Update() abort
  if get(g:onesimus_update_state, 'running', 0)
    echohl WarningMsg
    echomsg 'Onesimus update is already running.'
    echohl None
    return 0
  endif

  let l:installer = fnamemodify($VIMRCDIR.'/install.sh', ':p')
  if !filereadable(l:installer) || !executable(l:installer)
    call s:ShowUpdateResult([
          \ 'The installed updater is missing or is not executable:',
          \ l:installer,
          \ ], 1)
    return 0
  endif

  let l:generation = get(g:onesimus_update_state, 'generation', 0) + 1
  let g:onesimus_update_state = {
        \ 'running': 1,
        \ 'generation': l:generation,
        \ 'installer': l:installer,
        \ 'stdout': [],
        \ 'stderr': [],
        \ 'exited': 0,
        \ 'closed': 0,
        \ 'exit_status': -1,
        \ }
  call s:Track('meta.update')

  " The shell updater loads this checkout directly.  Carry the active Vim and
  " plugin locations across that boundary so a deliberately customized setup
  " is synchronized instead of silently falling back to another installation.
  let l:environment = {
        \ 'ONESIMUS_VIM_BIN': fnamemodify(v:progpath, ':p'),
        \ 'ONESIMUS_PLUGIN_HOME': g:onesimus_plugin_home,
        \ 'ONESIMUS_VIM_PLUG': g:onesimus_vim_plug,
        \ }
  let l:job = job_start([l:installer, '--update'], {
        \ 'env': l:environment,
        \ 'in_io': 'null',
        \ 'out_mode': 'nl',
        \ 'err_mode': 'nl',
        \ 'out_cb': function('<SID>UpdateOutput',
        \   [l:generation, 'stdout']),
        \ 'err_cb': function('<SID>UpdateOutput',
        \   [l:generation, 'stderr']),
        \ 'exit_cb': function('<SID>UpdateExited', [l:generation]),
        \ 'close_cb': function('<SID>UpdateClosed', [l:generation]),
        \ })
  let g:onesimus_update_state.job = l:job

  if job_status(l:job) ==# 'fail'
        \ && get(g:onesimus_update_state, 'running', 0)
    let g:onesimus_update_state.exited = 1
    let g:onesimus_update_state.closed = 1
    call add(g:onesimus_update_state.stderr,
          \ 'Vim could not start '.l:installer.'.')
    call s:FinishUpdate(l:generation)
    return 0
  endif

  if get(g:onesimus_update_state, 'running', 0)
    echomsg 'Onesimus update started in the background.'
  endif
  return 1
endfunction

function! s:ToggleRelativeNumber() abort
  let &l:relativenumber = !&l:relativenumber
  call s:Track('ui.relative_number')
  echomsg 'Relative numbers '.(&l:relativenumber ? 'on' : 'off').'.'
endfunction

function! s:ToggleTree() abort
  if !PlugInstalled('nerdtree') || !exists(':NERDTreeToggle')
    echohl WarningMsg
    echomsg 'File tree needs NERDTree; run :PlugInstall nerdtree.'
    echohl None
    return
  endif
  call s:Track('nav.tree')
  NERDTreeToggle
endfunction

function! s:BuildTags() abort
  if !executable('ctags')
    echohl WarningMsg
    echomsg 'Project tags need Universal Ctags in PATH.'
    echohl None
    return
  endif
  call s:Track('nav.tags')
  execute '!ctags -R .'
endfunction

function! OnesimusConfigureIndentGuides() abort
  let l:width = max([1, shiftwidth()])
  let l:base = 'tab:│ ,trail:·,extends:›,precedes:‹,nbsp:␣'
  let &l:listchars = l:base

  " Vim 8.2 patchsets vary across distributions.  In particular, assigning an
  " unknown listchars item through :let may fail silently instead of raising
  " E474, so capability detection must read the value back.
  let l:wanted = l:base.',leadmultispace:│'.repeat(' ', l:width - 1)
  try
    let &l:listchars = l:wanted
  catch /^Vim\%((\a\+)\)\=:E\%(474\|1511\):/
    " Readback below owns the fallback.
  endtry
  if &l:listchars ==# l:wanted
    return
  endif

  " Older Vim can still draw repeated spaces, although it cannot limit the
  " marker to indentation.  This is a graceful visual fallback, not a version
  " guess, and the base value remains valid even on still older patchsets.
  let l:fallback = l:base.',multispace:│'.repeat(' ', l:width - 1)
  try
    let &l:listchars = l:fallback
  catch /^Vim\%((\a\+)\)\=:E\%(474\|1511\):/
    " Readback below owns the fallback.
  endtry
  if &l:listchars !=# l:fallback
    let &l:listchars = l:base
  endif
endfunction

function! s:ToggleIndentGuides() abort
  call OnesimusConfigureIndentGuides()
  let &l:list = !&l:list
  call s:Track('ui.indent_guides')
  echomsg 'Indent guides '.(&l:list ? 'on' : 'off').'.'
endfunction

function! s:ToggleParentheses() abort
  if PlugInstalled('rainbow') && exists(':RainbowToggle')
    RainbowToggle
  endif
  if exists(':DoMatchParen')
    DoMatchParen
  endif
  unlet! b:onesimus_parentheses_auto
  call s:Track('ui.parentheses')
endfunction

function! OnesimusConfigureParentheses() abort
  let l:wanted = index(['emacs', 'lisp', 'scheme'], &l:filetype) >= 0
  if l:wanted
    if PlugInstalled('rainbow') && exists(':RainbowToggleOn')
          \ && !exists('b:rainbow_confs')
      silent RainbowToggleOn
      let b:onesimus_parentheses_auto = 1
    endif
  elseif get(b:, 'onesimus_parentheses_auto', 0)
    if PlugInstalled('rainbow') && exists(':RainbowToggleOff')
      silent RainbowToggleOff
    endif
    unlet! b:onesimus_parentheses_auto
  endif
endfunction

command! OnesimusHome call <SID>OpenHome(1)
command! OnesimusHelp call <SID>OpenHelp()
command! OnesimusEditConfig call <SID>EditConfig()
command! OnesimusUpdate call <SID>Update()
command! OnesimusReload call OnesimusReloadConfig()
command! OnesimusToggleRelativeNumber call <SID>ToggleRelativeNumber()
command! OnesimusTree call <SID>ToggleTree()
command! OnesimusTags call <SID>BuildTags()
command! OnesimusIndentToggle call <SID>ToggleIndentGuides()
command! OnesimusParenthesisToggle call <SID>ToggleParentheses()
augroup onesimus_native_indent_guides
  autocmd!
  autocmd FileType * call OnesimusConfigureIndentGuides()
augroup END

augroup onesimus_home
  autocmd!
  autocmd VimEnter * call <SID>ScheduleHome()
augroup END

call OnesimusConfigureIndentGuides()
call OnesimusConfigureParentheses()
