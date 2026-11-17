" Plugin policy: explicit writes, lazy actions and actual-revision recovery.
let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
let g:onesimus_extra_themes = 0
let g:onesimus_developer_plugins = 0
let g:texinsitu_enabled = 0
let g:ale_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

function! s:Run() abort
  let l:work = resolve(tempname())
  call mkdir(l:work, 'p')
  let l:plugs = deepcopy(g:plugs)
  let l:order = copy(g:plugs_order)
  let l:overrides = deepcopy(get(g:, 'onesimus_plugin_overrides', {}))
  let l:state_home = $XDG_STATE_HOME
  try
    for l:name in ['seoul256.vim', 'vim-monokai', 'helpful.vim', 'vader.vim']
      call assert_false(has_key(g:plugs, l:name), l:name.' is optional')
    endfor
    let l:lock = json_decode(join(readfile($VIMRCDIR.'/plugins.lock.json'), "\n"))
    for [l:name, l:spec] in items(g:plugs)
      if has_key(l:spec, 'uri') && has_key(l:lock.plugins, l:name)
        call assert_equal(l:lock.plugins[l:name].commit, l:spec.commit)
      endif
    endfor

    call plug#('BaksiLi/texinsitu.vim', {'do': ':TexInsituInstall'})
    call assert_false(has_key(g:plugs['texinsitu.vim'], 'commit'),
          \ 'a later personal Plug declaration can follow the default branch')
    call assert_equal(':TexInsituInstall', g:plugs['texinsitu.vim'].do,
          \ 'following the default branch can retain the build hook')
    call assert_equal(l:lock.plugins.ale.commit, g:plugs.ale.commit,
          \ 'overriding one plugin leaves other pins in place')
    let g:plugs = deepcopy(l:plugs)

    call assert_false(exists('g:tabular_loaded'), 'Tabular stays unloaded at startup')
    new
    call setline(1, ['a=1', 'long=2'])
    1,2Tabularize /=
    call assert_equal(1, get(g:, 'tabular_loaded', 0))
    call assert_equal(['a    = 1', 'long = 2'], getline(1, '$'))
    bwipeout!

    let l:note = l:work.'/note.md'
    call writefile(['# Note', '', '<!-- vim-markdown-toc GFM -->', '',
          \ '* [Old title](#old-title)', '', '<!-- vim-markdown-toc -->', '',
          \ '## New title'], l:note)
    execute 'edit '.fnameescape(l:note)
    let l:before = getline(1, '$')
    write
    call assert_equal(l:before, readfile(l:note), 'saving never rewrites the TOC')
    UpdateToc
    call assert_match('New title', getline(5), 'the explicit update still works')
    bwipeout!

    let l:checkout = l:work."/plugin with a 'quote'"
    call mkdir(l:checkout, 'p')
    call system('git -C '.shellescape(l:checkout).' init -q')
    call assert_equal(0, v:shell_error)
    call system('git -C '.shellescape(l:checkout)
          \ .' -c user.name=Onesimus -c user.email=test@onesimus.invalid'
          \ .' commit -q --allow-empty -m fixture')
    call assert_equal(0, v:shell_error)
    let l:head = trim(system('git -C '.shellescape(l:checkout).' rev-parse HEAD'))
    let g:plugs = {
          \ 'remote': {'dir': l:checkout, 'uri': 'https://example.invalid/plugin.git',
          \            'commit': repeat('0', 40)},
          \ 'local': {'dir': l:checkout},
          \ 'missing': {'dir': l:work.'/missing', 'uri': 'https://example.invalid/missing.git'},
          \ }
    let l:snapshot = OnesimusPluginSnapshot(l:work.'/snapshot.vim')
    call assert_equal('rw-------', getfperm(l:snapshot))
    call assert_match(l:head, join(readfile(l:snapshot), "\n"))
    call assert_notmatch(repeat('0', 40), join(readfile(l:snapshot), "\n"),
          \ 'snapshot records installed HEAD instead of the requested commit')
    try
      call OnesimusPluginSnapshot(l:snapshot)
      call assert_report('snapshot must refuse an existing destination')
    catch /^Onesimus: plugin snapshot already exists:/
    endtry
    command! -nargs=* PlugUpdate let g:onesimus_test_restore = <q-args>
    execute 'source '.fnameescape(l:snapshot)
    call assert_equal(l:head, g:plugs.remote.commit)
    call assert_false(has_key(g:plugs.local, 'commit'), 'local checkout is never restored')
    call assert_equal('--sync', g:onesimus_test_restore)
    let $XDG_STATE_HOME = l:work.'/state'
    One snapshot
    call assert_true(filereadable(g:onesimus_last_plugin_snapshot),
          \ 'snapshot without an argument records installed revisions')
    call assert_match('^'.escape(l:work, '\.^$~[]').'/state/onesimus/plugin-snapshots/',
          \ g:onesimus_last_plugin_snapshot)
    execute 'One snapshot '.l:work.'/explicit.vim'
    call assert_equal(l:work.'/explicit.vim', g:onesimus_last_plugin_snapshot,
          \ 'snapshot also accepts an explicit filename')
    let g:plugs.remote.uri = 'https://example.invalid/another-fork.git'
    let g:plugs.remote.commit = 'personal'
    execute 'source '.fnameescape(l:snapshot)
    call assert_equal('personal', g:plugs.remote.commit, 'restore respects a different fork')

    let g:onesimus_plugin_overrides = {'vim-cogitatum': l:checkout}
    call OnesimusPlugin('BaksiLi/vim-cogitatum', {'do': 'must not run', 'tag': 'unused'})
    call assert_false(has_key(g:plugs['vim-cogitatum'], 'uri'))
    call assert_false(has_key(g:plugs['vim-cogitatum'], 'do'))
    call assert_false(has_key(g:plugs['vim-cogitatum'], 'tag'))
    let g:onesimus_plugin_overrides['vim-cogitatum'] = l:work.'/missing'
    try
      call OnesimusPlugin('BaksiLi/vim-cogitatum')
      call assert_report('a missing local override must not fall back to remote')
    catch /^Onesimus: local plugin checkout not found:/
    endtry

    let g:plugs = l:plugs
    let g:plugs_order = l:order
    let g:onesimus_plugin_overrides = l:overrides
    let g:onesimus_extra_themes = 1
    let g:onesimus_developer_plugins = 1
    execute 'source '.fnameescape($MYVIMDOT)
    for l:name in ['seoul256.vim', 'vim-monokai', 'helpful.vim', 'vader.vim']
      call assert_true(has_key(g:plugs, l:name), l:name.' can be enabled')
      call assert_equal(l:lock.plugins[l:name].commit, g:plugs[l:name].commit)
    endfor
  catch
    call assert_report(v:exception.' at '.v:throwpoint)
  finally
    let $XDG_STATE_HOME = l:state_home
    call delete(l:work, 'rf')
  endtry
  if empty(v:errors) | qa! | endif
  for l:error in v:errors | echomsg l:error | endfor
  cquit
endfunction
autocmd VimEnter * ++nested call <SID>Run()
