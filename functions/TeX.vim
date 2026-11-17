" A small, stable TeX control plane.  VimTeX owns TeX semantics and compiler
" lifecycle; Onesimus owns explicit-write policy, remote-friendly UX, and
" actionable feedback.

function! s:Track(action) abort
  if exists('*OnesimusTrack')
    call OnesimusTrack(a:action)
  endif
endfunction

function! s:IsTeXBuffer() abort
  return &l:filetype ==# 'tex' && &l:buftype ==# ''
endfunction

function! s:RequireTeXBuffer() abort
  if s:IsTeXBuffer()
    return 1
  endif
  call OnesimusNotify('TEX WORKFLOW', ['This action needs a normal TeX buffer.'], 1)
  return 0
endfunction

function! s:Compiler() abort
  return exists('b:vimtex.compiler')
        \ && type(b:vimtex.compiler) is v:t_dict
        \ ? b:vimtex.compiler : {}
endfunction

function! s:GetBuildMode() abort
  let l:compiler = s:Compiler()
  return !empty(l:compiler)
        \ ? get(l:compiler, 'onesimus_build_mode', '')
        \ : get(b:, 'onesimus_tex_build_mode', '')
endfunction

function! s:SetBuildMode(mode) abort
  let l:compiler = s:Compiler()
  if !empty(l:compiler)
    if empty(a:mode)
      if has_key(l:compiler, 'onesimus_build_mode')
        call remove(l:compiler, 'onesimus_build_mode')
      endif
    else
      let l:compiler.onesimus_build_mode = a:mode
    endif
  elseif empty(a:mode)
    unlet! b:onesimus_tex_build_mode
  else
    let b:onesimus_tex_build_mode = a:mode
  endif
endfunction

function! OnesimusTexSourceState() abort
  if OnesimusHasExternalConflict()
    return 'CONFLICT'
  endif
  return &l:modified ? 'MODIFIED' : 'SAVED'
endfunction

function! OnesimusTexBuildRunning() abort
  let l:compiler = s:Compiler()
  if empty(l:compiler) || !has_key(l:compiler, 'is_running')
    return 0
  endif
  try
    return l:compiler.is_running()
  catch
    return 0
  endtry
endfunction

function! s:CompilerIssue() abort
  if exists(':VimtexCompileSS') != 2
    return 'VimTeX is unavailable; run :OnesimusUpdate or :PlugInstall vimtex.'
  endif
  let l:compiler = s:Compiler()
  if empty(l:compiler)
    return 'VimTeX did not initialize compiler state for this buffer.'
  endif
  if !get(l:compiler, 'enabled', 0)
    let l:program = get(l:compiler, 'executable', get(l:compiler, 'name', 'compiler'))
    return l:program.' (the configured VimTeX compiler) is unavailable.'
  endif
  if !exists('b:vimtex') || type(b:vimtex) isnot v:t_dict
        \ || !has_key(b:vimtex, 'is_compileable')
    return 'VimTeX did not initialize a TeX project for this buffer.'
  endif
  try
    if !b:vimtex.is_compileable()
      return 'VimTeX could not identify a compileable main TeX file.'
    endif
  catch
    return 'VimTeX could not validate the main TeX file: '.v:exception
  endtry
  return ''
endfunction

function! OnesimusTexLiveAvailable() abort
  let l:compiler = s:Compiler()
  return !empty(l:compiler) && get(l:compiler, 'enabled', 0)
        \ && get(l:compiler, 'continuous', 0)
endfunction

function! OnesimusTexBuildState() abort
  let l:issue = s:CompilerIssue()
  if !empty(l:issue)
    return l:issue =~# '^VimTeX' ? 'NO VIMTEX'
          \ : (l:issue =~# '^latexmk' ? 'NO LATEXMK' : 'NOT BUILDABLE')
  endif
  if OnesimusTexBuildRunning()
    return s:GetBuildMode() ==# 'once'
          \ ? 'BUILDING ONCE' : 'LIVE BUILD'
  endif
  if exists('b:vimtex.compiler') && type(b:vimtex.compiler) is v:t_dict
    let l:status = get(b:vimtex.compiler, 'status', 0)
  else
    let l:status = 0
  endif
  if l:status == 2 && get(s:Compiler(), 'onesimus_pdf_stale', 0)
    return 'PDF OUTDATED'
  endif
  return l:status == 2 ? 'LAST OK' : (l:status == 3 ? 'LAST FAILED' : 'STOPPED')
endfunction

function! OnesimusTexStatusline() abort
  if &l:filetype !=# 'tex'
    return ''
  endif
  return '[TeX '.OnesimusTexBuildState().']'
endfunction

function! OnesimusTexMenuTitle() abort
  return 'TEX · '.OnesimusTexSourceState().' · '.OnesimusTexBuildState()
endfunction

function! OnesimusTexMenuSummary() abort
  let l:build = OnesimusTexBuildState()
  let l:labels = {'STOPPED': 'PDF idle', 'LAST OK': 'Last build OK',
        \ 'PDF OUTDATED': 'PDF needs rebuilding',
        \ 'LAST FAILED': 'Build failed', 'BUILDING ONCE': 'Building PDF',
        \ 'LIVE BUILD': 'Live build on'}
  return (&l:modified ? 'Unsaved' : 'No unsaved edits').' · '
        \ .get(l:labels, l:build, 'Compiler unavailable')
endfunction

function! s:MainFile() abort
  if exists('b:vimtex') && type(b:vimtex) is v:t_dict
        \ && !empty(get(b:vimtex, 'tex', ''))
    return b:vimtex.tex
  endif
  return expand('%:p')
endfunction

function! s:PdfFile() abort
  if exists('b:vimtex.compiler') && type(b:vimtex.compiler) is v:t_dict
        \ && has_key(b:vimtex.compiler, 'get_file')
    try
      let l:pdf = b:vimtex.compiler.get_file('pdf')
      if !empty(l:pdf)
        return l:pdf
      endif
    catch
      " The deterministic fallback below is enough for a useful SSH hint.
    endtry
    let l:info = get(b:vimtex.compiler, 'file_info', {})
    let l:root = !empty($VIMTEX_OUTPUT_DIRECTORY)
          \ ? $VIMTEX_OUTPUT_DIRECTORY : get(b:vimtex.compiler, 'out_dir', '')
    if empty(l:root)
      let l:root = get(l:info, 'root', '')
    elseif l:root !~# '^/'
      let l:root = get(l:info, 'root', '').'/'.l:root
    endif
    let l:jobname = get(l:info, 'jobname', '')
    if !empty(l:root) && !empty(l:jobname)
      return simplify(l:root.'/'.l:jobname.'.pdf')
    endif
  endif
  return fnamemodify(s:MainFile(), ':r').'.pdf'
endfunction


function! s:PrepareBuild() abort
  if !s:RequireTeXBuffer()
    return 0
  endif
  if empty(bufname('%'))
    call OnesimusNotify('SAVE BEFORE BUILD', [
          \ 'This TeX buffer has no filename yet.',
          \ 'Use :saveas once; after that F5 safely saves and builds it.',
          \ ], 1)
    return 0
  endif
  call OnesimusCheckExternalChanges(1)
  let l:dirty = exists('b:vimtex') ? OnesimusTexProjectDirty(b:vimtex) : []
  call filter(l:dirty, 'v:val != bufnr("%")')
  if !empty(l:dirty)
    call OnesimusNotify('SAVE OTHER CHANGES BEFORE BUILDING', [
          \ 'Unsaved or externally changed sources in this paper:',
          \ '  '.join(map(l:dirty, 'fnamemodify(bufname(v:val), ":~:.")'), ', '),
          \ 'Review/save these buffers, then press F5. Nothing was saved yet.',
          \ ], 1)
    return 0
  endif
  let l:issue = s:CompilerIssue()
  if !empty(l:issue)
    call OnesimusNotify('TEX BUILD UNAVAILABLE — SOURCE NOT SAVED', [l:issue,
          \ 'Use \\s if you only want to save.'], 1)
    return 0
  endif
  let b:onesimus_tex_saved_for_build = &l:modified
  if !OnesimusSafeUpdate()
    return 0
  endif
  let l:issue = s:CompilerIssue()
  if !empty(l:issue)
    call OnesimusNotify('SOURCE SAVED; TEX BUILD UNAVAILABLE', [l:issue], 1)
    return 0
  endif
  return 1
endfunction

function! OnesimusTexSave() abort
  if !s:RequireTeXBuffer()
    return 0
  endif
  let l:was_modified = &l:modified
  if !OnesimusSafeUpdate()
    return 0
  endif
  if !l:was_modified
    call OnesimusNotify('SOURCE IN SYNC', [
          \ 'Any collaborator edit detected on disk has been loaded.',
          \ ], 0)
    return 1
  endif
  call s:Track('tex.save')
  let l:next = OnesimusTexBuildRunning()
        \ ? (s:GetBuildMode() ==# 'live'
        \   ? 'The live build will pick up this explicit save.'
        \   : 'The current one-shot may predate this save; press F5 to replace it.')
        \ : 'Press F5 to build once, or \. then l for a live build.'
  call OnesimusNotify('SOURCE SAVED', [l:next], 0)
  return 1
endfunction

function! OnesimusTexSync() abort
  if !s:RequireTeXBuffer()
    return 0
  endif
  call OnesimusCheckExternalChanges(0)
  call s:Track('tex.sync')
  if OnesimusHasExternalConflict()
    if getftype(expand('%:p')) ==# ''
      call OnesimusNotify('SOURCE DELETED OUTSIDE VIM', [
            \ 'The local buffer is preserved; nothing was written.',
            \ 'Press \. then x to recreate it, or :saveas for another path.',
            \ ], 1)
    elseif !filereadable(expand('%:p'))
      call OnesimusNotify('SOURCE UNREADABLE ON DISK', [
            \ 'The local buffer is preserved; nothing was written.',
            \ 'Fix the disk path permissions or mount, then press \. and re-check.',
            \ ], 1)
    else
      call OnesimusNotify('SOURCE CONFLICT', [
            \ 'Local and disk edits are both preserved.',
            \ 'Press \. then d to compare them; nothing was written.',
            \ ], 1)
    endif
  elseif &l:modified
    call OnesimusNotify('DISK CHECKED', [
          \ 'No external conflict is known.',
          \ 'Your local changes remain unsaved.',
          \ ], 0)
  else
    call OnesimusNotify('SOURCE IN SYNC', [
          \ 'Any collaborator edit detected on disk has been loaded.',
          \ ], 0)
  endif
  return 1
endfunction

function! OnesimusTexBuildOnce(...) abort
  if !s:PrepareBuild()
    return 0
  endif
  let l:compiler = s:Compiler()
  let l:compiler.onesimus_open_after_build = get(a:000, 0, 0)
  if OnesimusTexBuildRunning()
    if s:GetBuildMode() ==# 'live'
      if get(l:compiler, 'status', 0) == 2
            \ && !get(l:compiler, 'onesimus_pdf_stale', 0)
            \ && get(l:compiler, 'onesimus_pdf_revision', {})
            \    ==# OnesimusTexProjectRevision(b:vimtex)
        if l:compiler.onesimus_open_after_build
          let l:compiler.onesimus_open_after_build = 0
          return OnesimusTexOpenProject(b:vimtex)
        endif
        return 1
      endif
      if get(l:compiler, 'status', 0) != 1
        " A failed/idle watcher may have nothing new to react to. F5 still
        " means build now; restart watching with latexmk's force-rebuild flag.
        try
          VimtexStop
          call s:SetBuildMode('live')
          VimtexCompile -g
        catch
          let l:compiler.onesimus_open_after_build = 0
          call OnesimusNotify('LIVE BUILD COULD NOT RESTART', [v:exception], 1)
          return 0
        endtry
      endif
      call OnesimusNotify('LIVE BUILD ACTIVE', [
            \ 'Source safely saved; latexmk is already watching the project.',
            \ 'The live build will pick it up; press \. then l to stop it.',
            \ ], 0)
      return 1
    endif
    " F5 means the newest saved source is compiled.  Replacing an older
    " in-flight one-shot is deterministic and avoids pretending it watches.
    try
      VimtexStop
    catch
      call OnesimusNotify('SOURCE SAVED; BUILD NOT RESTARTED', [v:exception], 1)
      return 0
    endtry
  endif
  let l:restarted = s:GetBuildMode() ==# 'once'
  call s:SetBuildMode('once')
  try
    VimtexCompileSS
  catch
    call s:SetBuildMode('')
    call OnesimusNotify('SOURCE SAVED; TEX BUILD FAILED TO START', [v:exception], 1)
    return 0
  endtry
  let l:start_status = get(s:Compiler(), 'status', -1)
  if !OnesimusTexBuildRunning() && index([2, 3], l:start_status) < 0
    call s:SetBuildMode('')
    call OnesimusNotify('SOURCE SAVED; TEX BUILD DID NOT START', [
          \ 'Open \\o then c for the compiler log.',
          \ ], 1)
    return 0
  endif
  call s:Track('tex.build_once')
  call OnesimusNotify('TEX BUILD STARTED', [
        \ l:restarted
        \   ? 'Replaced the older one-shot with a build of the newest source.'
        \   : get(b:, 'onesimus_tex_saved_for_build', 0)
        \   ? 'Source saved safely; building it once in the background.'
        \   : 'Building the already-saved source once in the background.',
        \ 'A collaborator disk change would have blocked the save and build.',
        \ ], 0)
  return 1
endfunction

function! OnesimusTexToggleLiveBuild() abort
  if !s:RequireTeXBuffer()
    return 0
  endif
  if OnesimusTexBuildRunning()
    let l:mode = s:GetBuildMode()
    try
      VimtexStop
    catch
      call OnesimusNotify('LIVE BUILD COULD NOT STOP', [v:exception], 1)
      return 0
    endtry
    call s:SetBuildMode('')
    call s:Track('tex.live_build')
    call OnesimusNotify(l:mode ==# 'live' ? 'LIVE BUILD STOPPED' : 'BUILD STOPPED', [], 0)
    return 1
  endif
  if !OnesimusTexLiveAvailable()
    call OnesimusNotify('NO LIVE BUILD MODE', [
          \ 'The configured VimTeX backend does not support watching.',
          \ 'Nothing was saved; use F5 for a one-shot build.',
          \ ], 1)
    return 0
  endif
  if !s:PrepareBuild()
    return 0
  endif
  call s:SetBuildMode('live')
  try
    VimtexCompile
  catch
    call s:SetBuildMode('')
    call OnesimusNotify('SOURCE SAVED; LIVE BUILD FAILED TO START', [v:exception], 1)
    return 0
  endtry
  if !OnesimusTexBuildRunning()
    call s:SetBuildMode('')
    call OnesimusNotify('SOURCE SAVED; LIVE BUILD DID NOT START', [
          \ 'Open \\o then c for the compiler log.',
          \ ], 1)
    return 0
  endif
  call s:Track('tex.live_build')
  call OnesimusNotify('LIVE BUILD STARTED', [
        \ get(b:, 'onesimus_tex_saved_for_build', 0)
        \   ? 'Source saved safely; latexmk now watches the project.'
        \   : 'latexmk now watches the saved project on this machine.',
        \ 'Later edits are saved only by :write, \\s, or another F5.',
        \ ], 0)
  return 1
endfunction

function! s:RunVimtex(command, title, action) abort
  if !s:RequireTeXBuffer()
    return 0
  endif
  if exists(':'.a:command) != 2
    call OnesimusNotify(a:title,
          \ ['VimTeX is unavailable; run :OnesimusUpdate or :PlugInstall vimtex.'],
          \ 1)
    return 0
  endif
  try
    execute a:command
  catch
    call OnesimusNotify(a:title, [v:exception], 1)
    return 0
  endtry
  call s:Track(a:action)
  return 1
endfunction

function! s:CanLocatePDF() abort
  return !&l:modified && !get(s:Compiler(), 'onesimus_pdf_stale', 0)
        \ && (!exists('b:vimtex') || empty(OnesimusTexProjectDirty(b:vimtex)))
endfunction

function! OnesimusTexView() abort
  if !s:RequireTeXBuffer() | return 0 | endif
  call OnesimusCheckExternalChanges(0)
  call OnesimusTexRefreshBuildStates()
  let l:options = {}
  if s:CanLocatePDF()
    let l:options.forward = {'file': expand('%:p'), 'line': line('.'), 'column': col('.')}
  endif
  return OnesimusTexBrowser(s:PdfFile(), s:MainFile(), l:options)
endfunction

function! OnesimusTexOpenExternal() abort
  if !s:RequireTeXBuffer() | return 0 | endif
  let l:pdf = s:PdfFile()
  if !filereadable(l:pdf)
    call OnesimusNotify('PDF NOT BUILT YET', ['Press F5 to build '.l:pdf], 1)
    return 0
  endif
  if OnesimusPreviewHeadless()
    call OnesimusNotify('OPEN PDF ON YOUR DEVICE', [
          \ 'Use Download PDF in the browser, then open that copy on your device.'], 0)
    return 0
  endif
  return OnesimusOpenExternal(l:pdf)
endfunction

function! OnesimusTexOutline() abort
  return s:RunVimtex('VimtexTocOpen', 'DOCUMENT OUTLINE', 'tex.outline')
endfunction

function! OnesimusTexErrors() abort
  return s:RunVimtex('VimtexErrors', 'COMPILE PROBLEMS', 'tex.errors')
endfunction

function! OnesimusTexOutput() abort
  return s:RunVimtex('VimtexCompileOutput', 'COMPILER OUTPUT', 'tex.output')
endfunction

function! OnesimusTexCountWords() abort
  " Some older Vim builds return -1, rather than 0, when PATH is empty.
  if executable('texcount') != 1
    call OnesimusNotify('WORD COUNT UNAVAILABLE',
          \ ['texcount is missing from PATH.'], 1)
    return 0
  endif
  return s:RunVimtex('VimtexCountWords', 'WORD COUNT', 'tex.word_count')
endfunction

function! s:SentenceConfig() abort
  if !empty(get(g:, 'onesimus_tex_sentence_config', ''))
    return fnamemodify(g:onesimus_tex_sentence_config, ':p')
  endif
  return fnamemodify($VIMRCDIR.'/config/latexindent-sentences.yaml', ':p')
endfunction

function! s:SentenceExecutable() abort
  return get(b:, 'ale_tex_latexindent_executable',
        \ get(g:, 'ale_tex_latexindent_executable', 'latexindent'))
endfunction

function! s:SentenceFailureLine(output) abort
  for l:line in split(a:output, "\n")
    let l:line = trim(l:line)
    if !empty(l:line)
      return strpart(l:line, 0, 180)
    endif
  endfor
  return 'latexindent returned no formatted source.'
endfunction

function! s:RunSentenceFormatter(text, config) abort
  let l:Runner = get(g:, 'OnesimusTexSentenceFormatterRunner', 0)
  if type(l:Runner) is v:t_func
    return call(l:Runner, [a:text, a:config])
  endif

  let l:executable = s:SentenceExecutable()
  if executable(l:executable) != 1
    return {
          \ 'status': 127,
          \ 'phase': 'startup',
          \ 'output': l:executable.' is missing from PATH.',
          \ }
  endif

  let l:version = system(shellescape(l:executable).' --version 2>&1')
  let l:version_status = v:shell_error
  if l:version_status != 0
    return {
          \ 'status': l:version_status,
          \ 'phase': 'startup',
          \ 'output': l:version,
          \ }
  endif

  let l:log = has('win32') || has('win64') ? 'NUL' : '/dev/null'
  let l:stderr = tempname()
  try
    " The final '-' is significant: without it latexindent may mistake the
    " optional -l value for the input file.  Do not use -s here; silent mode
    " suppresses the formatted source that this buffer-only action needs.
    let l:command = shellescape(l:executable)
          \ .' -m '.shellescape('-g='.l:log)
          \ .' '.shellescape('-l='.a:config)
          \ .' '.shellescape('-').' 2>'.shellescape(l:stderr)
    let l:output = system(l:command, a:text)
    let l:status = v:shell_error
    let l:error = filereadable(l:stderr)
          \ ? join(readfile(l:stderr), "\n") : ''
    return {
          \ 'status': l:status,
          \ 'phase': 'format',
          \ 'output': l:status == 0 ? l:output : l:error."\n".l:output,
          \ }
  finally
    call delete(l:stderr)
  endtry
endfunction

function! s:ReplaceBufferLines(lines) abort
  let l:new = empty(a:lines) ? [''] : a:lines
  let l:old_count = line('$')
  let l:new_count = len(l:new)
  let l:overlap = min([l:old_count, l:new_count])
  let l:changed = 0

  if getline(1, l:overlap) !=# l:new[: l:overlap - 1]
    call setline(1, l:new[: l:overlap - 1])
    let l:changed = 1
  endif
  if l:new_count > l:old_count
    if l:changed
      silent! undojoin
    endif
    call append(l:old_count, l:new[l:old_count :])
  elseif l:old_count > l:new_count
    if l:changed
      silent! undojoin
    endif
    call deletebufline(bufnr(''), l:new_count + 1, l:old_count)
  endif
endfunction

function! OnesimusTexSentenceLines() abort
  if !s:RequireTeXBuffer()
    return 0
  endif
  call OnesimusCheckExternalChanges(0)
  if OnesimusHasExternalConflict()
    call OnesimusNotify('SENTENCE FORMAT BLOCKED', [
          \ 'Local and disk edits must be resolved first.',
          \ 'Press \. then d to compare them; nothing was changed.',
          \ ], 1)
    return 0
  endif

  let l:config = s:SentenceConfig()
  if !filereadable(l:config)
    call OnesimusNotify('SENTENCE FORMATTER MISCONFIGURED', [
          \ 'Missing profile: '.l:config,
          \ ], 1)
    return 0
  endif

  let l:input = join(getline(1, '$'), "\n").(&l:endofline ? "\n" : '')
  redraw
  echomsg 'Onesimus: finding TeX sentence boundaries…'
  let l:result = s:RunSentenceFormatter(l:input, l:config)
  if type(l:result) isnot v:t_dict
    call OnesimusNotify('SENTENCE FORMATTER FAILED', [
          \ 'The formatter returned an invalid result; the buffer was unchanged.',
          \ ], 1)
    return 0
  endif
  if get(l:result, 'status', 1) != 0
    let l:startup = get(l:result, 'phase', 'format') ==# 'startup'
    let l:lines = [s:SentenceFailureLine(get(l:result, 'output', ''))]
    if l:startup
      call add(l:lines, has('macunix')
            \ ? 'Repair option: `brew install latexindent`, then retry \. n.'
            \ : 'Install latexindent and its Perl dependencies, then retry \. n.')
      call add(l:lines,
            \ 'Run `latexindent --version` in the shell to verify the repair.')
    else
      call add(l:lines,
            \ 'latexindent could not format this buffer; inspect its error above.')
    endif
    call add(l:lines, 'The source buffer and disk file were not changed.')
    call OnesimusNotify(l:startup ? 'SENTENCE FORMATTER UNAVAILABLE'
          \ : 'SENTENCE FORMATTER FAILED', l:lines, 1)
    return 0
  endif

  let l:output = substitute(get(l:result, 'output', ''), "\r\n", "\n", 'g')
  if empty(l:output) && !empty(l:input)
    call OnesimusNotify('SENTENCE FORMATTER FAILED', [
          \ 'latexindent produced no source; the buffer was left unchanged.',
          \ ], 1)
    return 0
  endif
  let l:lines = split(l:output, "\n", 1)
  if !empty(l:lines) && l:lines[-1] ==# ''
    call remove(l:lines, -1)
  endif
  if l:lines ==# getline(1, '$')
    call OnesimusNotify('SENTENCE LINES ALREADY NORMALIZED', [
          \ 'No buffer or disk content changed.',
          \ ], 0)
    return 1
  endif

  let l:view = winsaveview()
  " Close any undo block created by the user's preceding edit.  All changes
  " inside ReplaceBufferLines are then one separate, predictable `u`.
  let &g:undolevels = &g:undolevels
  call s:ReplaceBufferLines(l:lines)
  call winrestview(l:view)
  call s:Track('tex.sentence_lines')
  call OnesimusNotify('SENTENCE LINES READY — NOT SAVED', [
        \ 'latexindent changed only this Vim buffer.',
        \ 'Review abbreviations, inline math, and the diff; u undoes once.',
        \ 'Press F5 to save + build, or \\o then d to compare with disk.',
        \ ], 0)
  return 1
endfunction

function! OnesimusTexCompareDisk() abort
  if !s:RequireTeXBuffer()
    return 0
  endif
  call s:Track('tex.compare_disk')
  return OnesimusDiffDisk()
endfunction

function! OnesimusTexWriteResolved() abort
  if !s:RequireTeXBuffer()
    return 0
  endif
  let l:result = OnesimusWriteResolved()
  if l:result
    call s:Track('tex.resolve_write')
  endif
  return l:result
endfunction

function! OnesimusTexUseDisk() abort
  if !s:RequireTeXBuffer()
    return 0
  endif
  let l:result = OnesimusUseDisk()
  if l:result
    call s:Track('tex.use_disk')
  endif
  return l:result
endfunction

function! s:NextStep() abort
  let l:source = OnesimusTexSourceState()
  if l:source ==# 'CONFLICT'
    if filereadable(expand('%:p'))
      return 'Next: \\d compares local and disk versions; nothing will overwrite either.'
    elseif getftype(expand('%:p')) ==# ''
      return 'Next: \\x recreates the deleted source, or :saveas keeps another path.'
    endif
    return 'Next: fix the unreadable disk path, then \\r re-checks it.'
  elseif l:source ==# 'MODIFIED'
    return 'Next: F5 saves + builds + previews, or \\s only saves.'
  elseif OnesimusTexBuildRunning()
    return s:GetBuildMode() ==# 'live'
          \ ? 'Next: edit, then \\s; the live build notices that disk write.'
          \ : 'Next: wait for this one-shot, or F5 to replace it with the newest source.'
  endif
  return 'Next: F5 builds + previews, or \\o then l starts a live build.'
endfunction

function! s:PreviewHelpLines() abort
  return [
        \ '  Browser PDF · last successful build · SyncTeX source navigation.',
        \ '  \\v opens/reuses it; current built source also locates the cursor.',
        \ '  Locate in source returns a point; selected text can enter Vim Visual.',
        \ '  \\d / :OnesimusDiff [file|git-ref] builds a latexdiff revision PDF.',
        \ '  Original and Changes both locate passages in the manuscript.',
        \ '  Cmd-F / Ctrl-F searches PDF text; Download saves a separate copy.',
        \ '  Vim owns the session; Zellij detach keeps it, quitting Vim ends it.',
        \ ]
endfunction

function! OnesimusTexStatus() abort
  if !s:RequireTeXBuffer()
    return 0
  endif
  call OnesimusCheckExternalChanges(0)
  let l:main = s:MainFile()
  let l:viewer = filereadable(s:PdfFile())
        \ ? 'browser PDF · Vim-owned session · SyncTeX'
        \ : 'PDF not built yet; F5 builds it'
  let l:formulas = exists('g:loaded_texinsitu') && texinsitu#enabled()
        \ ? 'rendered in place (texinsitu.vim); enter a formula to edit source'
        \ : 'raw source'
  call OnesimusPopup('TEX WORKFLOW', [
        \ '  Source   '.tolower(OnesimusTexSourceState()),
        \ '  Build    '.tolower(OnesimusTexBuildState()),
        \ '  Main     '.fnamemodify(l:main, ':~:.'),
        \ '  Viewer   '.l:viewer,
        \ '  Formulas '.l:formulas,
        \ '',
        \ '  '.s:NextStep(),
        \ '',
        \ '  Policy: idle/reload never saves; F5 explicitly saves + builds + previews.',
        \ '  Formatting/reflow is never tied to saving.',
        \ '  Recovery: Vim swap stores unsaved work without touching the .tex file.',
        \ '',
        \ ] + s:PreviewHelpLines())
  call s:Track('tex.status')
  return 1
endfunction

function! OnesimusTexHelp() abort
  call OnesimusPopup('TEX WRITING & COLLABORATION', [
        \ '  Daily loop',
        \ '    \        all actions; \\ opens current-file actions',
        \ '    F5       safe-save, build, then preview in the browser',
        \ '    \\v       open/reuse the browser PDF; locate when current',
        \ '    \\o k     let the browser PDF follow the cursor',
        \ '    \\s save · \\e errors · \\t outline · \\o more tools',
        \ '    Arrows / Enter or tap select; Left / Backspace goes back.',
        \ '',
        \ '  Source layout',
        \ '    Prefer one sentence per physical line plus soft screen wrap.',
        \ '    Use ) / ( or cis for sentences; t. remains line-local.',
        \ '    Do not join on open or hard-wrap/reflow every save.',
        \ '    \\n runs latexindent sentence lines in the buffer only.',
        \ '    It may also adjust indentation; it never saves automatically.',
        \ '    Review the result before saving; one u restores the prior buffer.',
        \ '',
        \ '  Formulas',
        \ '    Unicode formulas appear in place automatically; enter one to edit TeX.',
        \ '    Line, search, error and tag jumps open folds; Insert does too.',
        \ '    Leaving the formula renders it again; yanks and saves keep source.',
        \ '    \\m toggles automatic / raw formulas for this buffer.',
        \ '',
        \ '  PDF reader',
        \ '    \\v opens the browser without saving or building',
        \ ] + s:PreviewHelpLines() + [
        \ '',
        \ '  TeX dashes / ChkTeX warning 8',
        \ '    - compound word   -- range or peer relation   --- prose dash',
        \ '    Jordan--Hölder can be intentional: ChkTeX cannot infer names.',
        \ '    Put recurring exact exceptions in the paper''s .chktexrc.',
        \ '',
        \ '  Collaboration',
        \ '    Clean buffers reload disk edits; dirty conflicts block writes.',
        \ '    In conflict: compare, then choose disk or save the reviewed buffer.',
        \ '    If the disk file was deleted, \. x explicitly recreates it.',
        \ '    For isolated work, give the Harness a separate git worktree.',
        \ '',
        \ '  Terminal display',
        \ '    Orange/stale paint after scrolling: Ctrl-L redraws immediately.',
        \ ])
  call s:Track('tex.help')
  return 1
endfunction

function! OnesimusTexBuildFeedback(result, ...) abort
  let l:state = get(a:000, 0, get(b:, 'vimtex', {}))
  let l:compiler = get(l:state, 'compiler', {})
  if empty(l:compiler) | return | endif
  let l:open = get(l:compiler, 'onesimus_open_after_build', 0)
  let l:compiler.onesimus_open_after_build = 0
  if get(l:compiler, 'onesimus_build_mode', '') ==# 'once'
    let l:compiler.onesimus_build_mode = ''
  endif
  if a:result ==# 'success'
    if get(l:compiler, 'onesimus_pdf_stale', 0)
      let l:compiler.onesimus_open_after_build = l:open
            \ && get(l:compiler, 'onesimus_build_mode', '') ==# 'live'
      call OnesimusNotify('PDF NEEDS REBUILDING', [
            \ 'Tracked inputs changed during the build: '.get(l:state, 'tex', ''),
            \ l:compiler.onesimus_open_after_build
            \   ? 'Waiting for the next live result before opening the reader.'
            \   : 'Press F5 again to build the current saved sources.',
            \ ], 1)
      return
    endif
    if l:open
      call OnesimusTexOpenProject(l:state)
    else
      echomsg 'Onesimus: PDF built — '.fnamemodify(get(l:state, 'tex', ''), ':t')
    endif
  else
    call OnesimusNotify('PDF BUILD FAILED', [
          \ fnamemodify(get(l:state, 'tex', ''), ':~:.'),
          \ 'No reader was opened. Use \\e for errors; any PDF may be incomplete.',
          \ ], 1)
  endif
endfunction

function! OnesimusTexOpenProject(state) abort
  let l:compiler = get(a:state, 'compiler', {})
  let l:pdf = has_key(l:compiler, 'get_file') ? l:compiler.get_file('pdf')
        \ : fnamemodify(a:state.tex, ':r').'.pdf'
  return OnesimusTexBrowser(l:pdf, a:state.tex, {'reuse': 1, 'diff': {
        \ 'event': 'diff', 'files': OnesimusTexProjectFiles(a:state)}})
endfunction

function! OnesimusTexLocatePDF() abort
  if !s:RequireTeXBuffer() | return 0 | endif
  call OnesimusCheckExternalChanges(0)
  call OnesimusTexRefreshBuildStates()
  if !s:CanLocatePDF()
    call OnesimusNotify('BUILD BEFORE LOCATING', [
          \ 'PDF positions refer to the built source. Press F5, then \\v.',
          \ 'Use :OnesimusTexBrowser to read the previous PDF.',
          \ ], 1)
    return 0
  endif
  return OnesimusTexBrowser(s:PdfFile(), s:MainFile(), {'show': 0, 'forward': {
        \ 'file': expand('%:p'), 'line': line('.'), 'column': col('.')}})
endfunction

" Follow only an existing reader for current, saved source.
" Positions refer to the last build, so unsaved or outdated source is not followed.
let s:followed = get(s:, 'followed', '')

function! OnesimusTexToggleFollow() abort
  let g:onesimus_tex_follow = !get(g:, 'onesimus_tex_follow', 0)
  let s:followed = ''
  call OnesimusNotify(g:onesimus_tex_follow ? 'PDF FOLLOWS CURSOR' : 'PDF FOLLOW OFF',
        \ g:onesimus_tex_follow
        \ ? ['The browser PDF tracks the cursor in saved, built source.',
        \    'Open the reader with \\v; \\o k turns following off.']
        \ : ['\\v still locates the cursor on request.'], 0)
  call s:FollowCursor()
  return g:onesimus_tex_follow
endfunction

function! s:FollowCursor() abort
  if !get(g:, 'onesimus_tex_follow', 0) || !s:IsTeXBuffer() || !s:CanLocatePDF()
    return
  endif
  let l:key = expand('%:p').':'.line('.').':'.getftime(s:PdfFile())
  if l:key ==# s:followed | return | endif
  if OnesimusTexBrowserFollow(s:PdfFile(), s:MainFile(),
        \ {'file': expand('%:p'), 'line': line('.'), 'column': col('.')})
    let s:followed = l:key
  endif
endfunction

function! OnesimusTexBuildAndView() abort
  return OnesimusTexBuildOnce(1)
endfunction

function! OnesimusDiff(...) abort
  if !s:RequireTeXBuffer() | return 0 | endif
  call OnesimusCheckExternalChanges(0)
  call OnesimusTexRefreshBuildStates()
  if !s:CanLocatePDF()
    call OnesimusNotify('BUILD BEFORE COMPARING', [
          \ 'Press F5 to build the saved sources, then run :OnesimusDiff again.',
          \ 'The comparison never saves your draft.'], 1)
    return 0
  endif
  if !executable('latexdiff') || !executable('latexmk')
    call OnesimusNotify('TEX COMPARISON UNAVAILABLE', [
          \ 'latexdiff and latexmk are required on this host.'], 1)
    return 0
  endif
  " Resolve file names in Vim's cwd; a Git revision is resolved beside the source.
  let l:base = get(a:000, 0, '')
  let l:base = !empty(l:base) && filereadable(expand(l:base))
        \ ? fnamemodify(expand(l:base), ':p') : l:base
  let l:compiler = s:Compiler()
  let l:state = get(b:, 'vimtex', {'tex': s:MainFile()})
  return OnesimusTexBrowser(s:PdfFile(), s:MainFile(), {'reuse': 1, 'diff': {
        \ 'event': 'diff', 'base': l:base, 'files': OnesimusTexProjectFiles(l:state),
        \ 'engine': has_key(l:compiler, 'get_engine') ? l:compiler.get_engine() : '-pdf'}})
endfunction

command! OnesimusTexStatus call OnesimusTexStatus()
command! OnesimusTexHelp call OnesimusTexHelp()
command! OnesimusTexSave call OnesimusTexSave()
command! OnesimusTexSync call OnesimusTexSync()
command! OnesimusTexBuild call OnesimusTexBuildOnce()
command! OnesimusTexPreview call OnesimusTexBuildAndView()
command! OnesimusTexBrowser call OnesimusTexBrowser(s:PdfFile(), s:MainFile())
command! OnesimusTexLiveBuild call OnesimusTexToggleLiveBuild()
command! OnesimusTexView call OnesimusTexView()
command! OnesimusTexLocatePDF call OnesimusTexLocatePDF()
command! OnesimusTexFollow call OnesimusTexToggleFollow()
command! OnesimusTexOpenExternal call OnesimusTexOpenExternal()
command! OnesimusTexOutline call OnesimusTexOutline()
command! OnesimusTexErrors call OnesimusTexErrors()
command! OnesimusTexOutput call OnesimusTexOutput()
command! OnesimusTexCountWords call OnesimusTexCountWords()
command! -nargs=? -complete=file OnesimusDiff call OnesimusDiff(<q-args>)
command! OnesimusTexSentenceLines call OnesimusTexSentenceLines()
command! OnesimusTexCompareDisk call OnesimusTexCompareDisk()
command! OnesimusTexWriteResolved call OnesimusTexWriteResolved()
command! OnesimusTexUseDisk call OnesimusTexUseDisk()

augroup onesimus_tex_follow
  autocmd!
  autocmd CursorHold * call s:FollowCursor()
augroup END

augroup onesimus_tex_feedback
  autocmd!
  autocmd User VimtexEventCompileSuccess call OnesimusTexBuildFeedback('success')
  autocmd User VimtexEventCompileFailed call OnesimusTexBuildFeedback('failed')
augroup END
