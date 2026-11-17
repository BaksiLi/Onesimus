" VimTeX supplies the source graph; explicit bibliography declarations also
" matter before the first BibTeX/Biber run has created its dependency files.
function! OnesimusTexProjectFiles(state, ...) abort
  let l:root = get(a:state, 'root', fnamemodify(a:state.tex, ':h'))
  let l:files = [resolve(fnamemodify(a:state.tex, ':p'))]
  if has_key(a:state, 'get_sources')
    for l:file in a:state.get_sources()
      call add(l:files, resolve(simplify(l:file =~# '^/' ? l:file : l:root.'/'.l:file)))
    endfor
  endif
  let l:drafts = get(a:000, 0, 0)
  let l:seen = {}
  let l:i = 0
  while l:i < len(l:files)
    let l:file = l:files[l:i]
    let l:i += 1
    if has_key(l:seen, l:file) | continue | endif
    let l:seen[l:file] = 1
    if fnamemodify(l:file, ':e') !~# '^\%(tex\|ltx\)$' | continue | endif
    let l:buf = bufnr(l:file)
    let l:lines = l:drafts && bufloaded(l:buf) ? getbufline(l:buf, 1, '$')
          \ : (filereadable(l:file) ? readfile(l:file) : [])
    for l:line in l:lines
      let l:line = substitute(l:line, '\(^\|[^\\]\)\zs%.*', '', '')
      let l:pattern = '\\\(bibliography\|addbibresource\|input\|include\)\s*\%(\[[^]]*\]\s*\)\?{\([^}]*\)}'
      let l:start = 0
      while 1
        let l:match = matchlist(l:line, l:pattern, l:start)
        if empty(l:match) | break | endif
        let l:start = matchend(l:line, l:pattern, l:start)
        let l:ext = l:match[1] =~# 'bib' ? '.bib' : '.tex'
        for l:name in split(l:match[2], ',')
          let l:name = trim(l:name)
          if l:name =~# '\\' || empty(l:name) | continue | endif
          let l:name .= empty(fnamemodify(l:name, ':e')) ? l:ext : ''
          let l:path = l:name =~# '^/' ? l:name : l:root.'/'.l:name
          if !filereadable(l:path) && l:name !~# '^/'
            let l:relative = fnamemodify(l:file, ':h').'/'.l:name
            if filereadable(l:relative) | let l:path = l:relative | endif
          endif
          let l:path = resolve(simplify(l:path))
          if index(l:files, l:path) < 0 | call add(l:files, l:path) | endif
        endfor
      endwhile
    endfor
  endwhile
  for l:name in ['.latexmkrc', 'latexmkrc']
    if filereadable(l:root.'/'.l:name) | call add(l:files, l:root.'/'.l:name) | endif
  endfor
  let l:compiler = get(a:state, 'compiler', {})
  if has_key(l:compiler, 'get_file')
    let l:fls = l:compiler.get_file('fls')
    if filereadable(l:fls)
      for l:line in readfile(l:fls)
        if l:line !~# '^INPUT ' | continue | endif
        let l:path = strpart(l:line, 6)
        let l:path = resolve(simplify(l:path =~# '^/' ? l:path : l:root.'/'.l:path))
        if l:path =~# '/texmf-\%(dist\|var\)/' | continue | endif
        " Include project styles and figures, excluding generated aux files
        " and the installed TeX distribution. This is freshness tracking,
        " not a claim to capture the full toolchain reproducibly.
        if l:path =~# '\.\%(tex\|bib\|png\|jpe\?g\|pdf\|eps\)$'
              \ || (stridx(l:path, l:root.'/') == 0 && l:path =~# '\.\%(sty\|cls\|bst\)$')
          if l:path !=# l:compiler.get_file('pdf') | call add(l:files, l:path) | endif
        endif
      endfor
    endif
  endif
  return uniq(sort(l:files))
endfunction

function! OnesimusTexProjectRevision(state) abort
  let l:revision = {}
  for l:path in OnesimusTexProjectFiles(a:state)
    try
      if !filereadable(l:path)
        let l:revision[l:path] = 'missing'
      else
        let l:bytes = readfile(l:path, 'b')
        " Binary NULs become embedded newlines in readfile() strings. Retain
        " list boundaries so a changed image cannot alias LF and NUL bytes.
        let l:revision[l:path] = sha256(l:path =~# '\.\%(png\|jpe\?g\|pdf\|eps\)$'
              \ ? string(l:bytes) : join(l:bytes, "\n"))
      endif
    catch
      let l:revision[l:path] = 'unreadable'
    endtry
  endfor
  return l:revision
endfunction

function! OnesimusTexProjectDirty(state) abort
  let l:files = OnesimusTexProjectFiles(a:state, 1)
  let l:dirty = []
  for l:info in getbufinfo({'bufloaded': 1})
    let l:path = resolve(fnamemodify(l:info.name, ':p'))
    let l:other = getbufvar(l:info.bufnr, 'vimtex', {})
    let l:member = index(l:files, l:path) >= 0
          \ || l:other is a:state
          \ || (!empty(get(l:other, 'tex', ''))
          \   && resolve(fnamemodify(l:other.tex, ':p'))
          \      ==# resolve(fnamemodify(a:state.tex, ':p')))
    if l:member && (getbufvar(l:info.bufnr, '&modified') || OnesimusDiskChanged(l:info.bufnr))
      call add(l:dirty, l:info.bufnr)
    endif
  endfor
  return l:dirty
endfunction
