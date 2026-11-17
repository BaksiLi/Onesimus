" Keep source persistence and external-change detection separate.  Vim's
" timestamps handle normal reloads; a content fingerprint protects writing buffers
" from equal-size or timestamp-preserving collaborator writes.

function! s:IsGuardedBuffer(bufnr) abort
  return a:bufnr > 0 && OnesimusIsWritingBuffer(a:bufnr)
        \ && !empty(bufname(a:bufnr))
endfunction

function! s:DiskFingerprint(path) abort
  " filereadable() follows a valid symlink, while getftype() reports "link".
  " Papers are often reached through symlinked workspaces; a dangling link is
  " correctly treated as missing.
  if getftype(a:path) ==# ''
    return 'missing'
  endif
  if !filereadable(a:path)
    return 'unreadable:'.getftime(a:path).':'.getfsize(a:path)
  endif
  try
    " Writing sources are text; binary read mode preserves the final newline so
    " equal-size, same-timestamp rewrites are still distinguishable.
    return 'file:'.sha256(join(readfile(a:path, 'b'), "\n"))
  catch
    return 'unreadable:'.getftime(a:path).':'.getfsize(a:path)
  endtry
endfunction

function! s:DiskState(path) abort
  let l:type = getftype(a:path)
  if l:type ==# ''
    return 'missing'
  endif
  if l:type ==# 'link' && !filereadable(a:path)
    " A dangling symlink still names an existing filesystem object.  Replacing
    " it through :write! would destroy that link, so it is not a deletion.
    return 'unreadable'
  endif
  return filereadable(a:path) ? 'readable' : 'unreadable'
endfunction

function! s:TeXRootDirective(bufnr) abort
  if getbufvar(a:bufnr, '&filetype') !=# 'tex'
    return ''
  endif
  let l:pattern = exists('g:vimtex#re#tex_input_root')
        \ ? g:vimtex#re#tex_input_root
        \ : '\v^\c\s*\%\s*!?\s*tex\s+root\s*[=:]\s*\zs.*\ze\s*$'
  let l:roots = []
  for l:line in getbufline(a:bufnr, 1, 5)
    let l:root = matchstr(l:line, l:pattern)
    if !empty(l:root)
      call add(l:roots, l:root)
    endif
  endfor
  return join(l:roots, "\n")
endfunction

function! s:TeXStructuralFingerprint(bufnr) abort
  if getbufvar(a:bufnr, '&filetype') !=# 'tex'
    return ''
  endif
  let l:lines = getbufline(a:bufnr, 1, '$')
  let l:structure = []
  for l:line in l:lines
    if l:line =~# '^\s*%\s*!\?\s*TeX\s\+root\s*[=:]'
          \ || l:line =~# '\\\%(documentclass\|usepackage\|RequirePackage\|input\|include\|includeonly\|subfile\|import\|subimport\|inputfrom\|includefrom\|bibliography\|addbibresource\|graphicspath\)\>'
      call add(l:structure, substitute(l:line, '\s\+', ' ', 'g'))
    endif
  endfor
  return sha256(join(l:structure, "\n"))
endfunction

function! s:BufferFingerprint(bufnr, ...) abort
  let l:encoding = getbufvar(a:bufnr, '&fileencoding')
  let l:encoding = empty(l:encoding) ? &encoding : l:encoding
  " Vim strings cannot faithfully model embedded NUL bytes for this purpose.
  if l:encoding =~? '\%(ucs-\?[24]\|utf-\?16\|utf-\?32\)'
    return ''
  endif
  let l:fileformat = getbufvar(a:bufnr, '&fileformat')
  if index(['unix', 'dos', 'mac'], l:fileformat) < 0
    return ''
  endif
  let l:lines = getbufline(a:bufnr, 1, '$')
  let l:separator = l:fileformat ==# 'dos' ? "\r\n"
        \ : (l:fileformat ==# 'mac' ? "\r" : "\n")
  let l:bytes = join(l:lines, l:separator)
  " A clean single-empty-line buffer ambiguously represents either zero bytes
  " or one final newline.  Baseline recording can use the disk fingerprint;
  " once modified, Vim's actual fixeol rule below is deterministic.
  if l:lines ==# [''] && (!getbufvar(a:bufnr, '&modified')
        \ || getbufvar(a:bufnr, 'onesimus_preserved_clean_tick', -1) >= 0)
    return 'ambiguous-empty'
  endif
  let l:prospective_write = get(a:000, 0, 0)
  let l:writes_eol = getbufvar(a:bufnr, '&endofline')
        \ || (l:prospective_write && !getbufvar(a:bufnr, '&binary')
        \   && getbufvar(a:bufnr, '&fixendofline'))
  if l:writes_eol
    let l:bytes .= l:separator
  endif
  if l:encoding !=? &encoding
    let l:converted = iconv(l:bytes, &encoding, l:encoding)
    if empty(l:converted) && !empty(l:bytes)
      return ''
    endif
    let l:bytes = l:converted
  endif
  if getbufvar(a:bufnr, '&bomb') && l:encoding =~? '^utf-\?8$'
    let l:bytes = nr2char(0xfeff).l:bytes
  elseif getbufvar(a:bufnr, '&bomb')
    return ''
  endif
  return 'file:'.sha256(l:bytes)
endfunction

function! s:BufferTeXStructure(bufnr) abort
  return [s:TeXRootDirective(a:bufnr),
        \ s:TeXStructuralFingerprint(a:bufnr)]
endfunction

function! s:ReloadVimtexProject() abort
  if exists(':VimtexReloadState') != 2 || !exists('b:vimtex_id')
    return
  endif
  let l:old_id = b:vimtex_id
  let l:siblings = []
  for l:info in getbufinfo({'bufloaded': 1})
    if l:info.bufnr != bufnr('%')
          \ && getbufvar(l:info.bufnr, 'vimtex_id', -1) == l:old_id
      call add(l:siblings, l:info.bufnr)
    endif
  endfor
  silent VimtexReloadState
  " v2.15 removes the shared registry entry and initializes only the current
  " buffer.  Rebind every loaded sibling immediately so none retains a dead id.
  if exists('*vimtex#state#init')
    let l:origin = bufnr('%')
    let l:view = winsaveview()
    try
      for l:bufnr in l:siblings
        if bufloaded(l:bufnr)
              \ && getbufvar(l:bufnr, '&filetype') =~# '^\%(tex\|bib\)$'
          execute 'silent noautocmd keepalt keepjumps buffer '.l:bufnr
          unlet! b:vimtex b:vimtex_id b:vimtex_local
          call vimtex#state#init()
          call vimtex#state#init_local()
        endif
      endfor
    finally
      execute 'silent noautocmd keepalt keepjumps buffer '.l:origin
      call winrestview(l:view)
    endtry
  endif
endfunction

function! s:ClearReviewedDisk(bufnr) abort
  call setbufvar(a:bufnr, 'onesimus_reviewed_disk_fingerprint', '')
  call setbufvar(a:bufnr, 'onesimus_reviewed_disk_path', '')
endfunction

function! s:ClearPreservedClean(bufnr) abort
  call setbufvar(a:bufnr, 'onesimus_preserved_clean_fingerprint', '')
  call setbufvar(a:bufnr, 'onesimus_preserved_clean_tick', -1)
endfunction

function! OnesimusRecordDiskBaseline(bufnr) abort
  if !s:IsGuardedBuffer(a:bufnr)
    return
  endif
  let l:path = fnamemodify(bufname(a:bufnr), ':p')
  let l:disk = s:DiskFingerprint(l:path)
  if getbufvar(a:bufnr, '&modified')
    " A config reload or manual :setfiletype must never bless an unknown disk
    " revision beneath local edits.  Preserve an existing baseline; otherwise
    " force a reviewed comparison before the first write.
    if empty(getbufvar(a:bufnr, 'onesimus_disk_baseline', ''))
      call setbufvar(a:bufnr, 'onesimus_disk_baseline',
            \ l:disk ==# 'missing' ? 'missing' : 'unknown')
      call setbufvar(a:bufnr, 'onesimus_disk_baseline_path', l:path)
    endif
    return
  endif
  let l:buffer = s:BufferFingerprint(a:bufnr)
  call setbufvar(a:bufnr, 'onesimus_disk_baseline',
        \ l:disk ==# 'missing' || empty(l:buffer)
        \   || l:buffer ==# 'ambiguous-empty' ? l:disk : l:buffer)
  call setbufvar(a:bufnr, 'onesimus_disk_baseline_path', l:path)
  call setbufvar(a:bufnr, 'onesimus_external_change', '')
  call setbufvar(a:bufnr, 'onesimus_conflict_notified', 0)
  call s:ClearReviewedDisk(a:bufnr)
  call s:ClearPreservedClean(a:bufnr)
  if getbufvar(a:bufnr, '&filetype') ==# 'tex'
    call setbufvar(a:bufnr, 'onesimus_tex_synced_structure',
          \ s:BufferTeXStructure(a:bufnr))
  endif
endfunction

function! OnesimusFinishSourceWrite(bufnr, ...) abort
  if !s:IsGuardedBuffer(a:bufnr)
    return
  endif
  let l:target = fnamemodify(get(a:000, 0, bufname(a:bufnr)), ':p')
  let l:primary = fnamemodify(bufname(a:bufnr), ':p')
  " :write copy.tex must not rebase or conflict the original buffer.  :saveas
  " has already made the target the primary name by BufWritePost time.
  if l:target !=# l:primary
    return
  endif
  let l:disk = s:DiskFingerprint(l:target)
  let l:expected = s:BufferFingerprint(a:bufnr, 1)
  if l:expected ==# 'ambiguous-empty'
    let l:expected = 'file:'.sha256('')
  endif
  if !empty(l:expected) && l:disk !=# l:expected
    " An external writer landed between Vim's guarded pre-write check and the
    " post-write verification.  Make the divergence visible and writable only
    " through the reviewed-conflict path.
    call setbufvar(a:bufnr, 'onesimus_disk_baseline', l:expected)
    call setbufvar(a:bufnr, '&modified', 1)
    call s:MarkConflict(a:bufnr)
    return
  endif
  call setbufvar(a:bufnr, 'onesimus_disk_baseline', l:disk)
  call setbufvar(a:bufnr, 'onesimus_disk_baseline_path',
        \ l:target)
  call setbufvar(a:bufnr, 'onesimus_external_change', '')
  call setbufvar(a:bufnr, 'onesimus_conflict_notified', 0)
  call s:ClearReviewedDisk(a:bufnr)
  call s:ClearPreservedClean(a:bufnr)
endfunction

function! OnesimusDiskChanged(...) abort
  let l:bufnr = get(a:000, 0, bufnr('%'))
  if !s:IsGuardedBuffer(l:bufnr)
    return 0
  endif
  let l:baseline = getbufvar(l:bufnr, 'onesimus_disk_baseline', '')
  let l:path = fnamemodify(bufname(l:bufnr), ':p')
  let l:baseline_path = getbufvar(l:bufnr,
        \ 'onesimus_disk_baseline_path', l:path)
  if l:baseline_path !=# l:path
    return 1
  endif
  if empty(l:baseline)
    call OnesimusRecordDiskBaseline(l:bufnr)
    let l:baseline = getbufvar(l:bufnr, 'onesimus_disk_baseline', '')
    " An existing dirty buffer whose read revision is unknown is deliberately
    " assigned the sentinel above.  Treat it as changed instead of blessing
    " the current disk bytes on the first attempted write.
    if empty(l:baseline)
      return 1
    endif
  endif
  return s:DiskFingerprint(l:path) !=# l:baseline
endfunction

function! s:MarkConflict(bufnr) abort
  let l:path = fnamemodify(bufname(a:bufnr), ':p')
  let l:disk = s:DiskFingerprint(l:path)
  let l:reviewed = getbufvar(a:bufnr,
        \ 'onesimus_reviewed_disk_fingerprint', '')
  let l:reviewed_path = getbufvar(a:bufnr,
        \ 'onesimus_reviewed_disk_path', '')
  " A comparison authorizes only the exact path and bytes that were shown.
  " If the collaborator changes them again, make another review mandatory.
  if !empty(l:reviewed)
        \ && (l:reviewed_path !=# l:path || l:reviewed !=# l:disk)
    call s:ClearReviewedDisk(a:bufnr)
  endif
  call setbufvar(a:bufnr, 'onesimus_external_change', 'conflict')
  if getbufvar(a:bufnr, 'onesimus_conflict_notified', 0)
    return
  endif
  " Record the conflict immediately, but leave typing, selection and IME
  " composition alone. The next safe check will show the available actions.
  if index(['n', 'ce'], mode(1)) < 0
    return
  endif
  call setbufvar(a:bufnr, 'onesimus_conflict_notified', 1)
  let l:name = fnamemodify(bufname(a:bufnr), ':t')
  if l:disk ==# 'missing'
    call OnesimusNotify('SOURCE DELETED OUTSIDE VIM', [
          \ l:name.': the local buffer is preserved and nothing was written.',
          \ 'Press \. then x to recreate it, or :saveas to keep another path.',
          \ ], 1)
  elseif l:disk =~# '^unreadable:'
    call OnesimusNotify('SOURCE UNREADABLE ON DISK', [
          \ l:name.': the disk path exists but cannot be read safely.',
          \ 'The local buffer is preserved; fix permissions or the mount, then check again.',
          \ ], 1)
  else
    call OnesimusNotify('SOURCE CONFLICT', [
          \ l:name.': the disk file and Vim buffer both changed.',
          \ 'Both versions were kept; nothing was written.',
          \ 'Press \. then d to compare them.',
          \ ], 1)
  endif
endfunction

" A line number is not a reading position after text is inserted above it.
" Match the old line and its neighbours, falling back to the closest line
" when the passage itself was removed. No TeX parser is needed for this.
function! s:AnchorLine(old, new, line) abort
  let l:index = max([0, min([len(a:old) - 1, a:line - 1])])
  let l:best = min([a:line, len(a:new)])
  let l:score = -1
  for l:i in range(len(a:new))
    if a:new[l:i] !=# get(a:old, l:index, '') | continue | endif
    let l:score_here = 10
          \ + (l:i > 0 && l:index > 0 && a:new[l:i-1] ==# a:old[l:index-1] ? 100 : 0)
          \ + (get(a:new, l:i+1, '') ==# get(a:old,l:index+1, '') ? 100 : 0)
          \ - min([99, abs(l:i-l:index)])
    if l:score_here > l:score
      let l:best = l:i+1
      let l:score = l:score_here
    endif
  endfor
  return max([1, l:best])
endfunction

function! s:RefreshViews(bufnr, old) abort
  let l:new = getbufline(a:bufnr, 1, '$')
  for l:window in getwininfo()
    if l:window.bufnr != a:bufnr | continue | endif
    let l:view = getwinvar(l:window.winid, 'onesimus_refresh_view', {})
    if empty(l:view) | continue | endif
    let l:view.lnum = s:AnchorLine(a:old, l:new, l:view.lnum)
    let l:view.topline = s:AnchorLine(a:old, l:new, l:view.topline)
    call win_execute(l:window.winid, 'call winrestview('.string(l:view).')')
    call win_execute(l:window.winid, 'unlet! w:onesimus_refresh_view')
  endfor
endfunction

function! s:InspectBuffer(bufnr, reload_clean) abort
  if !s:IsGuardedBuffer(a:bufnr)
    return 1
  endif
  let l:path = fnamemodify(bufname(a:bufnr), ':p')
  let l:disk_state = s:DiskState(l:path)
  let l:preserved_tick = getbufvar(a:bufnr,
        \ 'onesimus_preserved_clean_tick', -1)
  if l:preserved_tick >= 0 && getbufvar(a:bufnr, '&modified')
    if getbufvar(a:bufnr, 'changedtick', -2) != l:preserved_tick
      " The synthetic modified flag has become a real local edit.
      call s:ClearPreservedClean(a:bufnr)
    elseif l:disk_state ==# 'readable'
      " The path recovered/reappeared and the user never edited the preserved
      " buffer.  Return it to clean state so the ordinary reload path can
      " reconcile the recovered disk revision without a fake merge.
      call setbufvar(a:bufnr, '&modified', 0)
      call s:ClearPreservedClean(a:bufnr)
    else
      call s:MarkConflict(a:bufnr)
      return 0
    endif
  endif
  if !OnesimusDiskChanged(a:bufnr)
    call setbufvar(a:bufnr, 'onesimus_external_change', '')
    call setbufvar(a:bufnr, 'onesimus_conflict_notified', 0)
    call s:ClearReviewedDisk(a:bufnr)
    return 1
  endif
  if getbufvar(a:bufnr, '&modified')
    if l:disk_state ==# 'readable'
          \ && s:BufferFingerprint(a:bufnr) ==# s:DiskFingerprint(l:path)
      call setbufvar(a:bufnr, '&modified', 0)
      call OnesimusRecordDiskBaseline(a:bufnr)
      return 1
    endif
    call s:MarkConflict(a:bufnr)
    return 0
  endif
  if l:disk_state ==# 'missing'
    " Deletion is not an ordinary clean reload: preserve the last readable
    " bytes in Vim and require an explicit choice before recreating the file.
    call setbufvar(a:bufnr, '&modified', 1)
    call setbufvar(a:bufnr, 'onesimus_preserved_clean_tick',
          \ getbufvar(a:bufnr, 'changedtick', -1))
    call s:MarkConflict(a:bufnr)
    return 0
  endif
  if l:disk_state ==# 'unreadable'
    " Never turn an ACL/permission/mount problem into permission to recreate
    " an existing path.  That would destroy bytes we could not snapshot.
    call setbufvar(a:bufnr, '&modified', 1)
    call setbufvar(a:bufnr, 'onesimus_preserved_clean_tick',
          \ getbufvar(a:bufnr, 'changedtick', -1))
    call s:MarkConflict(a:bufnr)
    return 0
  endif

  if a:reload_clean && a:bufnr == bufnr('%') && !&l:modified
    let l:approved_disk = s:DiskFingerprint(l:path)
    let l:old_lines = getline(1, '$')
    for l:window in getwininfo()
      if l:window.bufnr == a:bufnr
        call win_execute(l:window.winid, 'let w:onesimus_refresh_view = winsaveview()')
      endif
    endfor
    let l:old_tex_root = s:TeXRootDirective(a:bufnr)
    let l:old_tex_structure = s:TeXStructuralFingerprint(a:bufnr)
    " Re-reading the same buffer must not re-run a language ftplugin and
    " duplicate its buffer/window state.  Post-change consumers still receive
    " their dedicated event below.
    silent noautocmd keepjumps edit
    " :edit clears syntax items even with autocommands disabled. Reapply
    " syntax only; rerunning the filetype plugin would duplicate project state.
    let &l:syntax = &l:syntax
    call s:RefreshViews(a:bufnr, l:old_lines)
    let l:new_tex_root = s:TeXRootDirective(a:bufnr)
    let l:new_tex_structure = s:TeXStructuralFingerprint(a:bufnr)
    if (l:old_tex_root !=# l:new_tex_root
          \ || l:old_tex_structure !=# l:new_tex_structure)
          \ && exists(':VimtexReloadState') == 2
      " Root, includes, bibliography declarations, and preamble packages are
      " cached by VimTeX.  Body-only edits keep compiler/viewer state intact.
      let l:was_running = exists('*OnesimusTexBuildRunning')
            \ && OnesimusTexBuildRunning()
      call s:ReloadVimtexProject()
      echomsg 'Onesimus: TeX project structure changed; VimTeX state was reloaded.'
      if l:was_running
        call OnesimusNotify('TEX PROJECT CHANGED', [
              \ 'The previous live/current build was stopped while project state reloaded.',
              \ 'Press \. then l to restart live build, or F5 to build once.',
              \ ], 1)
      endif
    endif
    let l:loaded = s:BufferFingerprint(a:bufnr)
    let l:disk_after = s:DiskFingerprint(l:path)
    if l:disk_after !=# l:approved_disk
          \ || (l:loaded !=# 'ambiguous-empty' && l:loaded !=# l:approved_disk)
      call setbufvar(a:bufnr, '&modified', 1)
      call s:MarkConflict(a:bufnr)
      call OnesimusNotify('SOURCE CHANGED DURING RELOAD', [
            \ 'The disk changed again while Vim was reloading it.',
            \ 'The loaded revision remains in Vim; compare before writing.',
            \ ], 1)
      return 0
    endif
    call OnesimusRecordDiskBaseline(a:bufnr)
    silent doautocmd <nomodeline> FileChangedShellPost
    if s:DiskFingerprint(l:path) !=# l:approved_disk
      call setbufvar(a:bufnr, '&modified', 1)
      call setbufvar(a:bufnr, 'onesimus_disk_baseline', l:approved_disk)
      call setbufvar(a:bufnr, 'onesimus_disk_baseline_path', l:path)
      call s:MarkConflict(a:bufnr)
      call OnesimusNotify('SOURCE CHANGED AFTER RELOAD', [
            \ 'The disk changed again while reload hooks were finishing.',
            \ 'The loaded revision remains preserved; compare before writing.',
            \ ], 1)
      return 0
    endif
    echomsg 'Onesimus: reloaded externally changed '.fnamemodify(bufname('%'), ':t').'.'
  endif
  return !OnesimusDiskChanged(a:bufnr)
endfunction

function! OnesimusCheckExternalChanges(all_buffers) abort
  " Detection is safe during typing; replacing text is not. Scripted Ex mode
  " is also allowed so explicit checks and batch use have the same contract.
  let l:can_reload = index(['n', 'ce'], mode(1)) >= 0
  let l:targets = a:all_buffers
        \ ? map(getbufinfo({'bufloaded': 1}), 'v:val.bufnr')
        \ : [bufnr('%')]
  let l:all_clear = 1
  try
    for l:bufnr in l:targets
      if s:IsGuardedBuffer(l:bufnr)
        let l:origin = bufnr('%')
        let l:view = winsaveview()
        try
          if l:can_reload && l:bufnr != l:origin
                \ && !getbufvar(l:bufnr, '&modified') && OnesimusDiskChanged(l:bufnr)
            execute 'silent noautocmd keepalt keepjumps buffer '.l:bufnr
          endif
          if !s:InspectBuffer(l:bufnr, l:can_reload)
            let l:all_clear = 0
          endif
        finally
          if bufnr('%') != l:origin && bufexists(l:origin)
            execute 'silent noautocmd keepalt keepjumps buffer '.l:origin
            call winrestview(l:view)
          endif
        endtry
      elseif l:can_reload && !a:all_buffers
        execute 'checktime '.l:bufnr
      endif
    endfor
  catch
    call OnesimusNotify('DISK CHECK FAILED', [v:exception], 1)
    return 0
  endtry
  return l:all_clear
endfunction

function! OnesimusGuardSourceWrite(bufnr, ...) abort
  if !s:IsGuardedBuffer(a:bufnr)
    return
  endif
  let l:target = fnamemodify(get(a:000, 0, bufname(a:bufnr)), ':p')
  let l:baseline_path = getbufvar(a:bufnr,
        \ 'onesimus_disk_baseline_path', fnamemodify(bufname(a:bufnr), ':p'))
  if l:target !=# l:baseline_path
    " Writing a separate recovery copy is always useful when it is new.  An
    " existing destination is outside the revision we read, so refuse to
    " overwrite it implicitly.
    if getftype(l:target) ==# ''
      return
    endif
    call OnesimusNotify('RECOVERY WRITE BLOCKED', [
          \ 'The alternate destination already exists: '.fnamemodify(l:target, ':~'),
          \ 'Choose a new filename so neither version is overwritten.',
          \ ], 1)
    throw 'Onesimus: alternate TeX/Bib write target already exists'
  endif
  if getbufvar(a:bufnr, 'onesimus_allow_resolved_write', 0)
    call OnesimusFinalResolvedWriteGuard(a:bufnr, l:target)
    return
  endif
  if OnesimusDiskChanged(a:bufnr)
    call s:MarkConflict(a:bufnr)
    throw 'Onesimus: write blocked because the TeX/Bib file changed on disk'
  endif
endfunction

function! OnesimusGuardPartialSourceWrite(bufnr, target, append) abort
  if !s:IsGuardedBuffer(a:bufnr)
    return
  endif
  let l:target = fnamemodify(a:target, ':p')
  let l:primary = fnamemodify(bufname(a:bufnr), ':p')
  " A selected range may be exported as a new scratch/recovery file.  It must
  " never append or replace either the primary source or an existing path.
  if !a:append && l:target !=# l:primary && getftype(l:target) ==# ''
    return
  endif
  " FileWritePre/FileAppendPre mean a range or append, not a whole-buffer
  " source revision.  Treating one as a normal TeX save could truncate the
  " paper while also bypassing the baseline update contract.
  call OnesimusNotify('PARTIAL SOURCE WRITE BLOCKED', [
        \ 'Saving writes a complete source revision only.',
        \ 'Use :write for the whole buffer; a selection may go to a new scratch path.',
        \ ], 1)
  throw 'Onesimus: partial or append write blocked for guarded writing source'
endfunction

function! OnesimusFinalSafeWriteGuard(bufnr, target) abort
  let l:target = fnamemodify(a:target, ':p')
  let l:expected = getbufvar(a:bufnr,
        \ 'onesimus_safe_write_fingerprint', '')
  let l:expected_path = getbufvar(a:bufnr,
        \ 'onesimus_safe_write_path', '')
  if empty(l:expected) || l:expected_path !=# l:target
        \ || s:DiskFingerprint(l:target) !=# l:expected
    call s:MarkConflict(a:bufnr)
    throw 'Onesimus: disk revision changed during the safe-save transaction'
  endif
endfunction

function! OnesimusSafeUpdate(...) abort
  let l:create = get(a:000, 0, 0) && !empty(bufname('%'))
        \ && getftype(expand('%:p')) ==# ''
  let l:checked = OnesimusCheckExternalChanges(0)
  if !l:checked && !OnesimusHasExternalConflict()
    call OnesimusNotify('SOURCE NOT SAVED / BUILD BLOCKED', [
          \ 'The disk refresh could not finish. Resolve the reported error and try again.',
          \ ], 1)
    return 0
  endif
  if OnesimusHasExternalConflict()
    let l:disk = s:DiskFingerprint(expand('%:p'))
    if l:disk ==# 'missing'
      call OnesimusNotify('SOURCE NOT SAVED / BUILD BLOCKED', [
            \ 'The source was deleted outside Vim; this local buffer is preserved.',
            \ 'Press \. then x to recreate it, or :saveas for another path.',
            \ ], 1)
    elseif l:disk =~# '^unreadable:'
      call OnesimusNotify('SOURCE NOT SAVED / BUILD BLOCKED', [
            \ 'The disk path exists but cannot be read or snapshotted safely.',
            \ 'Fix its permissions or mount, then press \. and re-check.',
            \ ], 1)
    else
      call OnesimusNotify('SOURCE NOT SAVED / BUILD BLOCKED', [
            \ 'The disk file changed after this buffer was read.',
            \ 'Press \. then d to compare; x saves a reviewed merge.',
            \ ], 1)
    endif
    return 0
  endif
  let l:guarded_write = s:IsGuardedBuffer(bufnr('%')) && (&l:modified || l:create)
  if l:guarded_write
    let l:prewrite_buffer = s:BufferFingerprint(bufnr('%'), 1)
    if empty(l:prewrite_buffer)
      call OnesimusNotify('SOURCE NOT SAVED / BUILD BLOCKED', [
            \ 'This buffer encoding or BOM cannot be fingerprinted safely.',
            \ 'Convert the source to ordinary UTF-8 without BOM before guarded saving.',
            \ ], 1)
      return 0
    endif
    let b:onesimus_safe_write_path = fnamemodify(bufname('%'), ':p')
    let b:onesimus_safe_write_fingerprint =
          \ s:DiskFingerprint(b:onesimus_safe_write_path)
    " Install this after all persistent hooks so formatter/plugin writes that
    " happen within the same BufWritePre pass cannot invalidate our first
    " content check unnoticed.
    augroup onesimus_safe_write_final
      autocmd!
      execute 'autocmd BufWritePre <buffer='.bufnr('%').'> '
            \ .'call OnesimusFinalSafeWriteGuard('.bufnr('%')
            \ .', expand(''<afile>:p''))'
    augroup END
  endif
  try
    if l:create
      write
    else
      update
    endif
  catch
    call OnesimusNotify('SOURCE NOT SAVED', [v:exception], 1)
    return 0
  finally
    if l:guarded_write
      augroup onesimus_safe_write_final
        autocmd!
      augroup END
      unlet! b:onesimus_safe_write_path b:onesimus_safe_write_fingerprint
    endif
  endtry
  if l:guarded_write
    " BufWritePost hooks are allowed to touch the just-written path.  Verify
    " the transaction after every hook has returned, before F5 may compile.
    " Compute the expected bytes now: a legitimate BufWritePre formatter may
    " have changed the buffer since the disk-revision token was captured.
    let l:expected_buffer = s:BufferFingerprint(bufnr('%'), 1)
    if l:expected_buffer ==# 'ambiguous-empty'
      let l:expected_buffer = 'file:'.sha256('')
    endif
    let l:actual = s:DiskFingerprint(expand('%:p'))
    if empty(l:expected_buffer) || l:actual !=# l:expected_buffer
      setlocal modified
      call s:MarkConflict(bufnr('%'))
      call OnesimusNotify('SOURCE CHANGED DURING SAVE — BUILD BLOCKED', [
            \ 'The disk no longer matches the source revision Vim just wrote.',
            \ 'The local buffer remains preserved; press \. then d to compare.',
            \ ], 1)
      return 0
    endif
    call setbufvar(bufnr('%'), 'onesimus_disk_baseline', l:actual)
    call setbufvar(bufnr('%'), 'onesimus_disk_baseline_path', expand('%:p'))
    call setbufvar(bufnr('%'), 'onesimus_external_change', '')
    call setbufvar(bufnr('%'), 'onesimus_conflict_notified', 0)
    call OnesimusRefreshVimtexAfterLocalWrite(bufnr('%'))
  endif
  return 1
endfunction

function! OnesimusRefreshVimtexAfterLocalWrite(bufnr) abort
  if getbufvar(a:bufnr, '&filetype') !=# 'tex'
    return
  endif
  let l:current = s:BufferTeXStructure(a:bufnr)
  let l:synced = getbufvar(a:bufnr, 'onesimus_tex_synced_structure', l:current)
  if l:current !=# l:synced && a:bufnr == bufnr('%')
        \ && exists(':VimtexReloadState') == 2
    let l:was_running = exists('*OnesimusTexBuildRunning')
          \ && OnesimusTexBuildRunning()
    call s:ReloadVimtexProject()
    echomsg 'Onesimus: local TeX project structure changed; VimTeX state was reloaded.'
    if l:was_running
      call OnesimusNotify('TEX PROJECT CHANGED', [
            \ 'The previous live/current build stopped while project state reloaded.',
            \ 'Press \. then l to restart live build, or F5 to build once.',
            \ ], 1)
    endif
  endif
  call setbufvar(a:bufnr, 'onesimus_tex_synced_structure', l:current)
endfunction

function! OnesimusTeXStructureChanged(bufnr) abort
  if getbufvar(a:bufnr, '&filetype') !=# 'tex'
    return 0
  endif
  let l:current = s:BufferTeXStructure(a:bufnr)
  return l:current !=# getbufvar(a:bufnr,
        \ 'onesimus_tex_synced_structure', l:current)
endfunction

function! s:SnapshotReviewedDisk(path, reviewed) abort
  let l:state_base = empty($XDG_STATE_HOME)
        \ ? expand('~/.local/state') : expand($XDG_STATE_HOME)
  let l:root = l:state_base.'/onesimus/vim/reviewed'
  if !(isdirectory(l:root) || mkdir(l:root, 'p', 0700))
    return ''
  endif
  let l:tail = fnamemodify(a:path, ':t')
  let l:extension = fnamemodify(l:tail, ':e')
  let l:name = substitute(empty(l:extension) ? l:tail
        \ : fnamemodify(l:tail, ':r'),
        \ '[^[:alnum:]._-]', '_', 'g')
  let l:suffix = empty(l:extension) ? '.snapshot'
        \ : '.snapshot.'.substitute(l:extension, '[^[:alnum:]_-]', '_', 'g')
  let l:snapshot = ''
  for l:index in range(0, 99)
    let l:candidate = printf('%s/%s-%s-%d-%02d%s', l:root,
          \ strftime('%Y%m%d-%H%M%S'), l:name, getpid(), l:index, l:suffix)
    if getftype(l:candidate) ==# ''
      let l:snapshot = l:candidate
      break
    endif
  endfor
  if empty(l:snapshot)
    return ''
  endif
  try
    if writefile(readfile(a:path, 'b'), l:snapshot, 'b') != 0
          \ || s:DiskFingerprint(l:snapshot) !=# a:reviewed
      call delete(l:snapshot)
      return ''
    endif
    if exists('*setfperm')
      call setfperm(l:snapshot, 'rw-------')
    endif
  catch
    call delete(l:snapshot)
    return ''
  endtry
  return l:snapshot
endfunction

function! OnesimusFinalResolvedWriteGuard(bufnr, target) abort
  let l:target = fnamemodify(a:target, ':p')
  let l:reviewed = getbufvar(a:bufnr,
        \ 'onesimus_reviewed_disk_fingerprint', '')
  let l:reviewed_path = getbufvar(a:bufnr,
        \ 'onesimus_reviewed_disk_path', '')
  if empty(l:reviewed) || l:reviewed_path !=# l:target
        \ || s:DiskFingerprint(l:target) !=# l:reviewed
    call s:MarkConflict(a:bufnr)
    throw 'Onesimus: reviewed disk revision changed before the write'
  endif
endfunction

function! OnesimusWriteResolved() abort
  if !OnesimusHasExternalConflict()
    return OnesimusSafeUpdate()
  endif
  let l:path = fnamemodify(bufname('%'), ':p')
  let l:disk_state = s:DiskState(l:path)
  let l:missing = l:disk_state ==# 'missing'
  if l:disk_state ==# 'unreadable'
    call OnesimusNotify('SOURCE NOT SAVED', [
          \ 'The disk path exists but cannot be read or snapshotted safely.',
          \ 'Fix its permissions or mount before resolving this conflict.',
          \ ], 1)
    return 0
  endif
  let l:reviewed = get(b:, 'onesimus_reviewed_disk_fingerprint', '')
  let l:reviewed_path = get(b:, 'onesimus_reviewed_disk_path', '')
  if !l:missing && (empty(l:reviewed) || l:reviewed_path !=# l:path
        \ || s:DiskFingerprint(l:path) !=# l:reviewed)
    call s:MarkConflict(bufnr('%'))
    call OnesimusNotify('REVIEW EXPIRED — SOURCE NOT SAVED', [
          \ empty(l:reviewed)
          \   ? 'Open \. then d and review the current disk version first.'
          \   : 'The disk changed again after you opened the comparison.',
          \ 'Both versions remain preserved; compare again before writing.',
          \ ], 1)
    return 0
  endif
  if l:missing
    if confirm('Recreate the externally deleted source from this preserved buffer?',
          \ "&Cancel\n&Recreate source", 1, 'WarningMsg') != 2
      return 0
    endif
    let b:onesimus_reviewed_disk_fingerprint = 'missing'
    let b:onesimus_reviewed_disk_path = l:path
  endif
  return OnesimusCommitReviewedSource()
endfunction

" Write the revision explicitly reviewed in the comparison. The command's
" label expresses the replacement action; the disk snapshot preserves recovery.
" Missing files require a separate recreation choice above.
function! OnesimusCommitReviewedSource() abort
  if !OnesimusHasExternalConflict()
    return 0
  endif
  let l:path = fnamemodify(bufname('%'), ':p')
  let l:disk_state = s:DiskState(l:path)
  let l:missing = l:disk_state ==# 'missing'
  if l:disk_state ==# 'unreadable'
    call OnesimusNotify('SOURCE NOT SAVED', [
          \ 'The disk path exists but cannot be read or snapshotted safely.',
          \ ], 1)
    return 0
  endif
  let l:reviewed = get(b:, 'onesimus_reviewed_disk_fingerprint', '')
  let l:reviewed_path = get(b:, 'onesimus_reviewed_disk_path', '')
  let l:expected_buffer = s:BufferFingerprint(bufnr('%'), 1)
  if l:expected_buffer ==# 'ambiguous-empty'
    let l:expected_buffer = 'file:'.sha256('')
  endif
  if empty(l:expected_buffer)
    call OnesimusNotify('SOURCE NOT SAVED', [
          \ 'This buffer encoding or BOM cannot be fingerprinted safely.',
          \ ], 1)
    return 0
  endif
  if empty(l:reviewed) || l:reviewed_path !=# l:path
        \ || s:DiskFingerprint(l:path) !=# l:reviewed
    call s:MarkConflict(bufnr('%'))
    call OnesimusNotify('REVIEW EXPIRED — SOURCE NOT SAVED', [
          \ 'The disk revision no longer matches the one you approved.',
          \ 'Review the current state again before writing.',
          \ ], 1)
    return 0
  endif
  let l:snapshot = ''
  if !l:missing
    let l:snapshot = s:SnapshotReviewedDisk(l:path, l:reviewed)
    if empty(l:snapshot)
      call OnesimusNotify('SOURCE NOT SAVED', [
            \ 'Could not create and verify a private snapshot of the disk version.',
            \ ], 1)
      return 0
    endif
  endif
  let b:onesimus_allow_resolved_write = 1
  " Register this last, so a later pre-write hook cannot silently invalidate
  " the exact disk revision that was reviewed.  This narrows the editor-side
  " race; truly simultaneous writers still belong in separate worktrees.
  augroup onesimus_resolved_write_final
    autocmd!
    execute 'autocmd BufWritePre <buffer='.bufnr('%').'> '
          \ .'call OnesimusFinalResolvedWriteGuard('.bufnr('%')
          \ .', expand(''<afile>:p''))'
  augroup END
  try
    " Keep Vim's native backup/write handling. Vim can additionally ask its
    " timestamp confirmation; even :write! cannot suppress that check.
    write
  catch
    call OnesimusNotify('SOURCE NOT SAVED', [v:exception], 1)
    return 0
  finally
    augroup onesimus_resolved_write_final
      autocmd!
    augroup END
    unlet! b:onesimus_allow_resolved_write
  endtry
  let l:actual = s:DiskFingerprint(l:path)
  " BufWritePre formatters legitimately change the bytes to be saved.
  let l:expected_buffer = s:BufferFingerprint(bufnr('%'), 1)
  if l:expected_buffer ==# 'ambiguous-empty'
    let l:expected_buffer = 'file:'.sha256('')
  endif
  if l:actual !=# l:expected_buffer
    setlocal modified
    call s:MarkConflict(bufnr('%'))
  endif
  if &l:modified || OnesimusDiskChanged()
    call OnesimusNotify('SOURCE NOT SAVED', [
          \ 'The disk diverged during the write; the buffer remains marked local.',
          \ 'Open \. then d and review the current disk revision again.',
          \ ], 1)
    return 0
  endif
  call OnesimusNotify(l:missing ? 'DELETED SOURCE RECREATED' : 'REVIEWED SOURCE SAVED',
        \ l:missing
        \ ? ['The preserved local buffer is now the new disk revision.']
        \ : ['Reviewed disk snapshot: '.fnamemodify(l:snapshot, ':~')], 0)
  return 1
endfunction

function! OnesimusUseDisk() abort
  if !s:IsGuardedBuffer(bufnr('%'))
    return 0
  endif
  let l:disk_state = s:DiskState(expand('%:p'))
  if l:disk_state ==# 'missing'
    call OnesimusNotify('NO DISK VERSION', [
          \ 'This source was deleted outside Vim; the preserved buffer was not changed.',
          \ 'Use :saveas with a new path, or review and recreate it explicitly.',
          \ ], 1)
    return 0
  endif
  if l:disk_state ==# 'unreadable'
    call OnesimusNotify('DISK VERSION UNREADABLE', [
          \ 'The existing path cannot be loaded safely; the local buffer was preserved.',
          \ ], 1)
    return 0
  endif
  let l:path = expand('%:p')
  let l:approved_disk = s:DiskFingerprint(l:path)
  if &l:modified
    let l:choice = confirm(
          \ "Discard this Vim buffer and load the disk version?\n"
          \ .'This intentionally discards the unsaved local edits.',
          \ "&Cancel\n&Use disk version", 1, 'WarningMsg')
    if l:choice != 2
      return 0
    endif
  endif
  " The confirmation is a human-scale race window.  Never discard local
  " bytes for a disk revision different from the one the prompt described.
  if s:DiskState(l:path) !=# 'readable'
        \ || s:DiskFingerprint(l:path) !=# l:approved_disk
    call s:MarkConflict(bufnr('%'))
    call OnesimusNotify('DISK CHANGED — LOCAL BUFFER PRESERVED', [
          \ 'The disk revision changed while the confirmation was open.',
          \ 'Nothing was replaced; press \. then d to inspect it again.',
          \ ], 1)
    return 0
  endif
  let l:local = {
        \ 'lines': getline(1, '$'), 'fileformat': &l:fileformat,
        \ 'fileencoding': &l:fileencoding, 'endofline': &l:endofline,
        \ 'bomb': &l:bomb,
        \ }
  let l:view = winsaveview()
  let l:old_tex_root = s:TeXRootDirective(bufnr('%'))
  let l:old_tex_structure = s:TeXStructuralFingerprint(bufnr('%'))
  try
    silent noautocmd keepjumps edit!
  catch
    silent keepjumps %delete _
    call setline(1, l:local.lines)
    let &l:fileformat = l:local.fileformat
    let &l:fileencoding = l:local.fileencoding
    let &l:endofline = l:local.endofline
    let &l:bomb = l:local.bomb
    setlocal modified
    call winrestview(l:view)
    call OnesimusNotify('DISK VERSION NOT LOADED', [v:exception], 1)
    return 0
  endtry
  let l:loaded = s:BufferFingerprint(bufnr('%'))
  let l:disk_after = s:DiskFingerprint(l:path)
  if l:disk_after !=# l:approved_disk
        \ || (l:loaded !=# 'ambiguous-empty' && l:loaded !=# l:approved_disk)
    silent keepjumps %delete _
    call setline(1, l:local.lines)
    let &l:fileformat = l:local.fileformat
    let &l:fileencoding = l:local.fileencoding
    let &l:endofline = l:local.endofline
    let &l:bomb = l:local.bomb
    setlocal modified
    call winrestview(l:view)
    call s:MarkConflict(bufnr('%'))
    call OnesimusNotify('DISK CHANGED — LOCAL BUFFER PRESERVED', [
          \ 'The disk changed while Vim was loading the approved revision.',
          \ 'The previous local bytes were restored; compare again.',
          \ ], 1)
    return 0
  endif
  call winrestview(l:view)
  let l:new_tex_root = s:TeXRootDirective(bufnr('%'))
  let l:new_tex_structure = s:TeXStructuralFingerprint(bufnr('%'))
  if (l:old_tex_root !=# l:new_tex_root
        \ || l:old_tex_structure !=# l:new_tex_structure)
        \ && exists(':VimtexReloadState') == 2
    let l:was_running = exists('*OnesimusTexBuildRunning')
          \ && OnesimusTexBuildRunning()
    call s:ReloadVimtexProject()
    echomsg 'Onesimus: TeX project structure changed; VimTeX state was reloaded.'
    if l:was_running
      call OnesimusNotify('TEX PROJECT CHANGED', [
            \ 'The previous live/current build was stopped while project state reloaded.',
            \ 'Press \. then l to restart live build, or F5 to build once.',
            \ ], 1)
    endif
  endif
  call OnesimusRecordDiskBaseline(bufnr('%'))
  silent doautocmd <nomodeline> FileChangedShellPost
  if s:DiskFingerprint(l:path) !=# l:approved_disk
    setlocal modified
    let b:onesimus_disk_baseline = l:approved_disk
    let b:onesimus_disk_baseline_path = l:path
    call s:MarkConflict(bufnr('%'))
    call OnesimusNotify('DISK CHANGED AFTER LOAD', [
          \ 'The disk changed again while project state was refreshing.',
          \ 'The loaded revision remains preserved; compare before writing.',
          \ ], 1)
    return 0
  endif
  call OnesimusNotify('DISK VERSION LOADED', ['The Vim buffer was replaced explicitly.'], 0)
  return 1
endfunction

function! OnesimusHasExternalConflict(...) abort
  let l:bufnr = get(a:000, 0, bufnr('%'))
  return l:bufnr > 0 && bufexists(l:bufnr)
        \ && getbufvar(l:bufnr, '&modified')
        \ && getbufvar(l:bufnr, 'onesimus_external_change', '') ==# 'conflict'
endfunction

function! OnesimusDiffDisk() abort
  let l:path = expand('%:p')
  if empty(l:path) || !filereadable(l:path) || &l:buftype !=# ''
    call OnesimusNotify('COMPARE WITH DISK',
          \ ['Save this as a normal file before comparing it.'], 1)
    return 0
  endif

  let l:disk = s:DiskFingerprint(l:path)
  let l:origin = win_getid()
  let l:existing = getwinvar(l:origin, 'onesimus_disk_diff_scratch', 0)
  if l:existing > 0 && bufexists(l:existing)
    if getbufvar(l:existing, 'onesimus_disk_fingerprint', '') ==# l:disk
          \ && getbufvar(l:existing, 'onesimus_disk_path', '') ==# l:path
      let b:onesimus_reviewed_disk_fingerprint = l:disk
      let b:onesimus_reviewed_disk_path = l:path
      let l:existing_window = bufwinid(l:existing)
      if l:existing_window > 0
        call win_gotoid(l:existing_window)
        return l:existing
      endif
    endif
    execute 'silent! bwipeout '.l:existing
  endif
  let l:origin_bufnr = bufnr('%')
  call s:ClearReviewedDisk(l:origin_bufnr)
  let l:filetype = &l:filetype
  let l:fileencoding = &l:fileencoding
  let l:fileformat = &l:fileformat
  let l:bomb = &l:bomb

  try
    noautocmd keepalt aboveleft vertical new
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
    " Let Vim decode the disk side with the source buffer's text options.  A
    " raw readfile() would expose CR bytes for DOS files and mojibake for legacy
    " encodings, which is exactly where a conflict view must remain legible.
    let &l:fileencoding = l:fileencoding
    let &l:fileformat = l:fileformat
    let &l:bomb = l:bomb
    execute 'silent noautocmd 0read ++edit '.fnameescape(l:path)
    " The authorization covers the bytes read above, not merely an earlier
    " stat.  If the collaborator changed them while the pane was opening,
    " discard it and make the user compare the current revision again.
    let l:shown = s:BufferFingerprint(bufnr('%'))
    if l:shown ==# 'ambiguous-empty'
      let l:shown = l:disk
    endif
    if s:DiskFingerprint(l:path) !=# l:disk || l:shown !=# l:disk
      throw 'Onesimus: disk changed while opening the comparison'
    endif
    " Syntax makes the disk side readable without firing a TeX FileType event
    " and accidentally creating a second VimTeX project/compiler state.
    let &l:syntax = l:filetype
    let l:scratch = bufnr('%')
    let b:onesimus_disk_fingerprint = l:disk
    let b:onesimus_disk_path = l:path
    call setwinvar(l:origin, 'onesimus_disk_diff_scratch', l:scratch)
    execute 'file '.fnameescape(printf('[disk] %s #%d',
          \ fnamemodify(l:path, ':t'), l:scratch))
    setlocal nomodified readonly nomodifiable
    nnoremap <silent><buffer> q :close<CR>
    diffthis
    execute 'autocmd BufWipeout <buffer='.l:scratch.'> '
          \ .'call OnesimusDiffDiskClosed('.l:origin.')'
  catch
    if win_getid() != l:origin && &l:buftype ==# 'nofile'
      silent! close!
    endif
    call s:ClearReviewedDisk(l:origin_bufnr)
    call OnesimusNotify('COMPARE WITH DISK FAILED', [v:exception], 1)
    return 0
  endtry

  call win_gotoid(l:origin)
  diffthis
  call setbufvar(l:origin_bufnr, 'onesimus_reviewed_disk_fingerprint', l:disk)
  call setbufvar(l:origin_bufnr, 'onesimus_reviewed_disk_path', l:path)
  call OnesimusNotify('COMPARE WITH DISK', [
        \ 'Disk copy: left, read-only.  Local buffer: right, editable.',
        \ 'Move to the disk pane and press q to close it.',
        \ 'After reviewing/merging locally, press \. then x to save it.',
        \ ], 0)
  return l:scratch
endfunction

function! OnesimusSourceStatusline() abort
  return OnesimusHasExternalConflict()
        \ ? '[DISK CONFLICT]' : ''
endfunction

function! OnesimusDiffDiskClosed(origin) abort
  if win_id2win(a:origin) > 0
    call win_execute(a:origin,
          \ 'diffoff | let w:onesimus_disk_diff_scratch = 0')
  endif
endfunction

command! OnesimusCheckDisk call OnesimusCheckExternalChanges(0)
command! OnesimusDiffDisk call OnesimusDiffDisk()
command! OnesimusSafeUpdate call OnesimusSafeUpdate()
command! OnesimusWriteResolved call OnesimusWriteResolved()
command! OnesimusUseDisk call OnesimusUseDisk()

augroup onesimus_external_changes
  autocmd!
  autocmd BufEnter,CursorHold,InsertLeave * call OnesimusCheckExternalChanges(0)
  autocmd FocusGained * call OnesimusCheckExternalChanges(1)
  if exists('##VimResume')
    autocmd VimResume * call OnesimusCheckExternalChanges(1)
  endif
  autocmd BufReadPost *
        \ call OnesimusRecordDiskBaseline(str2nr(expand('<abuf>')))
  autocmd BufWritePost * call OnesimusFinishSourceWrite(
        \ str2nr(expand('<abuf>')), expand('<afile>:p'))
  autocmd FileType * call OnesimusRecordDiskBaseline(bufnr('%'))
  autocmd BufWritePre * call OnesimusGuardSourceWrite(
        \ str2nr(expand('<abuf>')), expand('<afile>:p'))
  autocmd FileWritePre * call OnesimusGuardPartialSourceWrite(
        \ str2nr(expand('<abuf>')), expand('<afile>:p'), 0)
  autocmd FileAppendPre * call OnesimusGuardPartialSourceWrite(
        \ str2nr(expand('<abuf>')), expand('<afile>:p'), 1)
augroup END

" CursorHold fires once per idle spell. A single owned timer also catches
" Harness writes while the reader does nothing, and survives config reloads.
if exists('s:refresh_timer')
  call timer_stop(s:refresh_timer)
endif
function! s:PollExternalChanges(timer) abort
  if getcmdwintype() !=# '' || pumvisible() | return | endif
  call OnesimusCheckExternalChanges(1)
endfunction
let s:refresh_timer = timer_start(get(g:, 'onesimus_refresh_interval', 1000),
      \ function('s:PollExternalChanges'), {'repeat': -1})
