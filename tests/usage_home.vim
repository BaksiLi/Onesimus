" Local usage journal and Homepage integration test.
" Run with:
"   vim -Nu tests/usage_home.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 1
let g:onesimus_usage_state_dir = '/tmp/onesimus-usage-'.getpid()
execute 'source '.fnameescape($MYVIMDOT)

function! s:RunUsageTests() abort
  call OnesimusTrack('find.files')
  call OnesimusTrack('find.files')
  call OnesimusOffer('repl.open')
  call OnesimusObserveFiletype('markdown')
  call assert_false(has_key(g:onesimus_usage_runtime.eligible, 'writing.cjk'),
        \ 'segmentation is not offered until the jieba backend really loads')
  set filetype=lisp
  call assert_false(has_key(g:onesimus_usage_runtime.counts, 'ui.parentheses'),
        \ 'automatic FileType configuration is not counted as user intent')
  call assert_true(OnesimusUsageFlush())

  let l:files = globpath(g:onesimus_usage_state_dir, '*/*.json', 0, 1)
  call assert_equal(1, len(l:files), 'one process writes one session journal')
  let l:record = json_decode(join(readfile(l:files[0]), ''))
  call assert_equal(2, l:record.counts['find.files'])
  call assert_true(l:record.last['find.files'] > 0)
  call assert_equal(1, l:record.eligible['repl.open'])
  call assert_equal(1, l:record.filetypes.markdown)
  let l:encoded = json_encode(l:record)
  call assert_true(stridx(l:encoded, getcwd()) < 0,
        \ 'journal contains no working directory')
  call assert_false(has_key(l:record, 'paths'))
  call assert_equal(1, l:record.eligible['meta.help'],
        \ 'always-available actions are offered without being counted as used')
  call assert_equal(1, l:record.eligible['find.buffers'],
        \ 'installed plugin actions are eligible even when never used')

  " Malformed or partly written state must be ignored rather than breaking the
  " dashboard.  Missing last remains valid for the first journal format, but a
  " present value must be a dictionary.
  let l:month = fnamemodify(l:files[0], ':h')
  let l:malformed = l:month.'/malformed.json'
  call writefile([json_encode({
        \ 'v': 1, 'started_at': localtime(), 'updated_at': localtime(),
        \ 'counts': {'find.files': 1}, 'last': 0,
        \ 'eligible': {'find.files': 1}, 'filetypes': {}})], l:malformed)
  let l:bad_time = l:month.'/bad-time.json'
  call writefile([json_encode({
        \ 'v': 1, 'started_at': [], 'updated_at': localtime(),
        \ 'counts': {'find.files': 1}, 'last': {},
        \ 'eligible': {'find.files': 1}, 'filetypes': {}})], l:bad_time)
  let l:odd_last = l:month.'/odd-last.json'
  call writefile([json_encode({
        \ 'v': 1, 'started_at': localtime(), 'updated_at': localtime(),
        \ 'counts': {'find.files': 1}, 'last': {'find.files': []},
        \ 'eligible': {'find.files': 1}, 'filetypes': {}})], l:odd_last)

  let v:errmsg = ''
  let l:summary = OnesimusUsageSummary(7)
  call assert_notmatch('E691:', v:errmsg,
        \ 'bad journal field types never escape into dashboard arithmetic')
  call assert_equal(2, l:summary.sessions)
  call assert_equal(3, l:summary.actions['find.files'].count)
  call assert_true(l:summary.actions['find.files'].last > 0)
  call assert_equal(1, l:summary.filetypes.markdown)
  call delete(l:malformed)
  call delete(l:bad_time)
  call delete(l:odd_last)

  OnesimusStats 7
  call assert_equal('ONESIMUS / LOCAL USAGE', getline(1))
  call assert_equal('nofile', &l:buftype)
  call assert_match('change window', join(getline(1, '$'), "\n"))
  let l:stats_buffer = bufnr('')
  OnesimusStats 30
  call assert_equal(l:stats_buffer, bufnr(''),
        \ 'opening stats twice reuses the visible dashboard')
  call assert_match('Last 30 days', getline(3))
  close

  OnesimusHome
  let l:home = join(getline(1, '$'), "\n")
  call assert_match('ONESIMUS', l:home)
  call assert_match('Action guide', l:home)
  call assert_match('\\os for usage', l:home)
  call assert_match('Local only', l:home)
  let l:messages = execute('messages')
  call assert_notmatch('E495:', l:messages,
        \ 'unnamed dashboard buffers must not trip EditorConfig')
  call assert_notmatch('E95:', l:messages,
        \ 'reopening the dashboard must not collide with its buffer name')

  call writefile(['keep'], g:onesimus_usage_state_dir.'/KEEP')
  let l:month_dir = g:onesimus_usage_state_dir.'/'.strftime('%Y-%m')
  call mkdir(l:month_dir, 'p')
  call writefile(['keep'], l:month_dir.'/unrelated.json')
  OnesimusStatsReset!
  call assert_true(filereadable(g:onesimus_usage_state_dir.'/KEEP'),
        \ 'reset never recursively deletes the configurable state root')
  call assert_true(filereadable(l:month_dir.'/unrelated.json'),
        \ 'reset removes only filenames owned by the Onesimus journal')
  call assert_equal([l:month_dir.'/unrelated.json'], globpath(
        \ g:onesimus_usage_state_dir, '*/*.json', 0, 1))
  call assert_true(OnesimusUsageFlush())
  call assert_equal([l:month_dir.'/unrelated.json'], globpath(
        \ g:onesimus_usage_state_dir, '*/*.json', 0, 1),
        \ 'flushing after reset must not recreate an empty journal')

  call writefile(empty(v:errors) ? ['PASS'] : ['FAIL'] + v:errors,
        \ '/tmp/onesimus-usage-home-result')
  let g:onesimus_usage_enabled = 0
  call delete(g:onesimus_usage_state_dir, 'rf')
  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_usage_home_test
  autocmd!
  autocmd VimEnter * call <SID>RunUsageTests()
augroup END
