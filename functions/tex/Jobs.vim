" Bind VimTeX's Vim job transport to its owning project. VimTeX v2.15's
" default callbacks use current b:vimtex, which may be a different paper by
" the time a background build completes. Command construction, engines,
" stopping, logs and diagnostics remain owned by VimTeX.
function! OnesimusTexBindCompiler(...) abort
  let l:state = get(a:000, 0, get(b:, 'vimtex', {}))
  if !has_key(l:state, 'compiler') || has('nvim')
        \ || get(l:state.compiler, 'name', '') !=# 'latexmk'
    return
  endif
  let l:state.compiler.exec = function('s:Exec', [l:state])
endfunction

function! s:Exec(state, command) dict abort
  " Upstream's template allocates its output path once; give each job its
  " own log so concurrent papers cannot mix diagnostics.
  let self.output = tempname()
  call writefile([], self.output)
  let self.onesimus_generation = get(self, 'onesimus_generation', 0) + 1
  let l:job = {'state': a:state, 'compiler': self,
        \ 'generation': self.onesimus_generation, 'continuous': self.continuous}
  let self.onesimus_started_revision = OnesimusTexProjectRevision(a:state)
  let l:options = {'in_io': 'null', 'cwd': self.file_info.root,
        \ 'out_io': 'pipe', 'err_io': 'out',
        \ 'out_cb': function('s:Output', [l:job]),
        \ 'close_cb': function('s:Closed', [l:job]),
        \ 'exit_cb': function('s:Exit', [l:job])}
  let self.job = job_start(a:command, l:options)
endfunction

function! s:Owns(job) abort
  return get(a:job.compiler, 'onesimus_generation', -1) == a:job.generation
        \ && get(a:job.compiler, 'status', 0) != 0
endfunction

function! s:Output(job, channel, line) abort
  if !s:Owns(a:job) | return | endif
  call writefile([a:line], a:job.compiler.output, 'a')
  for l:Hook in get(a:job.compiler, 'hooks', [])
    call l:Hook(a:line)
  endfor
  if !a:job.continuous | return | endif
  let l:status = get({'vimtex_compiler_callback_compiling': 1,
        \ 'vimtex_compiler_callback_success': 2,
        \ 'vimtex_compiler_callback_failure': 3}, trim(a:line), 0)
  if l:status | call s:Result(a:job, l:status) | endif
endfunction

function! s:Exit(job, process, code) abort
  let a:job.exit_code = a:code
  call s:Finish(a:job)
endfunction

function! s:Closed(job, channel) abort
  let a:job.closed = 1
  call s:Finish(a:job)
endfunction

function! s:Finish(job) abort
  " Diagnostics must see the complete log, even if exit arrives before EOF.
  if !has_key(a:job, 'exit_code') || !get(a:job, 'closed', 0) | return | endif
  if !s:Owns(a:job) | return | endif
  if !a:job.continuous
    call s:Result(a:job, a:job.exit_code == 0 ? 2 : 3)
  elseif a:job.exit_code != 0
    call s:Result(a:job, 3)
  endif
endfunction

function! s:Result(job, status) abort
  let l:compiler = a:job.compiler
  let l:state = a:job.state
  let l:compiler.status = a:status
  if a:status == 1
    let l:compiler.onesimus_started_revision = OnesimusTexProjectRevision(l:state)
    return
  endif
  if a:status == 2
    let l:after = OnesimusTexProjectRevision(l:state)
    let l:before = get(l:compiler, 'onesimus_started_revision', {})
    " .fls discovers further inputs on the first build. Seed their baseline
    " for future checks; only known changes prove this result is already old.
    " This tracks freshness, not an immutable snapshot of a concurrent build.
    let l:compiler.onesimus_pdf_revision = l:after
    let l:compiler.onesimus_pdf_stale = !empty(filter(copy(l:before),
          \ 'get(l:after, v:key, "missing") !=# v:val'))
    call l:state.update_packages()
  endif
  " Only the owning buffer may receive VimTeX's buffer-local UI events.
  " Hidden projects still get accurate state and their requested PDF action.
  if get(b:, 'vimtex', {}) is l:state
    call vimtex#compiler#callback(a:status)
  else
    call OnesimusTexBuildFeedback(a:status == 2 ? 'success' : 'failed', l:state)
  endif
endfunction

function! OnesimusTexRefreshBuildStates() abort
  if !exists('*vimtex#state#list_all') | return | endif
  for l:state in vimtex#state#list_all()
    let l:compiler = get(l:state, 'compiler', {})
    if !empty(get(l:compiler, 'onesimus_pdf_revision', {}))
      let l:compiler.onesimus_pdf_stale =
            \ get(l:compiler, 'onesimus_pdf_stale', 0)
            \ || l:compiler.onesimus_pdf_revision !=# OnesimusTexProjectRevision(l:state)
    endif
  endfor
endfunction

augroup onesimus_tex_jobs
  autocmd!
  autocmd User VimtexEventInitPost call OnesimusTexBindCompiler()
  autocmd BufEnter,CursorHold,FocusGained,BufWritePost,FileChangedShellPost *.tex,*.ltx,*.bib
        \ call OnesimusTexRefreshBuildStates()
augroup END

" Reloading Onesimus also updates projects already initialized by VimTeX.
if exists('*vimtex#state#list_all')
  for s:state in vimtex#state#list_all()
    call OnesimusTexBindCompiler(s:state)
  endfor
  unlet! s:state
endif
