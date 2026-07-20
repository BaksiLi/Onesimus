" Run with:
"   vim -Nu tests/smoke.vim -i NONE -n -es

let $VIMRCDIR = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
let $MYVIMDOT = $VIMRCDIR.'/init.vim'
let g:startify_disable_at_vimenter = 1
let g:onesimus_usage_enabled = 0
execute 'source '.fnameescape($MYVIMDOT)

function! s:RunSmokeTests() abort
  call assert_equal(2, exists(':ALEInfo'), 'ALE command is available')
  call assert_equal(2, exists(':Clap'), 'vim-clap command is available')
  call assert_equal(2, exists(':GitGutter'), 'vim-gitgutter command is available')
  call assert_equal(2, exists(':OnesimusHealth'), 'health command is available')
  call assert_equal(2, exists(':OnesimusStats'), 'stats command is available')
  call assert_false(has_key(g:plugs, 'vim-lsp'), 'vim-lsp is not declared')
  call assert_false(has_key(g:plugs, 'vim-lsp-settings'),
        \ 'vim-lsp-settings is not declared')
  call assert_false(has_key(g:plugs, 'vim-which-key'),
        \ 'the compact action guide uses Vim popup windows directly')
  for l:name in ['vim-clap', 'markdown-preview.nvim', 'jieba.vim']
    if has_key(g:plugs, l:name)
      call assert_equal(v:t_string, type(g:plugs[l:name].do),
            \ l:name.' uses a synchronous vim-plug update hook')
    endif
  endfor
  if isdirectory($VIMRUNTIME.'/pack/dist/opt/editorconfig')
    call assert_false(has_key(g:plugs, 'editorconfig-vim'),
          \ 'Vim with native EditorConfig needs no duplicate plugin')
  else
    call assert_true(has_key(g:plugs, 'editorconfig-vim'),
          \ 'older Vim receives the official EditorConfig fallback')
  endif
  call assert_equal(1, g:ale_linters_explicit)
  call assert_equal(1, g:ale_completion_enabled)
  call assert_equal(['pylsp', 'ruff'], g:ale_linters.python)
  call assert_equal('<Plug>(ale_previous_wrap)', maparg('[d', 'n'))
  call assert_equal('<Plug>(ale_next_wrap)', maparg(']d', 'n'))
  call assert_match('OnesimusBufferSymbols', maparg('gs', 'n'))
  call assert_match('OnesimusBufferSymbols', maparg('<F2>', 'n'))
  call assert_equal(2, exists(':OnesimusClap'))
  call assert_match('OnesimusClap files', maparg('<leader>ff', 'n'))
  call assert_match('OnesimusClap marks', maparg('<leader>fm', 'n'))
  call assert_match('OnesimusFormat', maparg('<F6>', 'n'))
  call assert_match('Use k (up)', maparg('<Up>', 'n'))
  call assert_equal('', maparg('<Up>', 'x'),
        \ 'the Normal-mode HJKL hint does not pollute Visual mode')
  call assert_equal('', maparg('<Up>', 'o'),
        \ 'the Normal-mode HJKL hint does not pollute operator-pending mode')
  call assert_equal('', maparg('<C-n>', 'i'),
        \ 'ALE leaves Vim native keyword completion untouched')
  call assert_equal('', maparg('<C-p>', 'i'),
        \ 'ALE leaves Vim native backward completion untouched')
  call assert_equal([$VIMRCDIR.'/snippets'],
        \ g:UltiSnipsSnippetDirectories)
  call assert_true(stridx(&fileencodings, 'big5') >= 0)
  call assert_true(stridx(&completeopt, 'popup') >= 0)
  call assert_false(&autochdir)
  call assert_true(&list)
  call assert_match('\%(leadmultispace\|multispace\):', &l:listchars,
        \ 'indent guides follow the listchars capability of this Vim build')
  call assert_false(has_key(g:plugs, 'indentLine'))
  call assert_false(has_key(g:plugs, 'vim-markdown'))
  call assert_false(has_key(g:plugs, 'vim-markdown-folding'))
  call assert_false(exists('g:loaded_jieba_vim'),
        \ 'jieba bridge stays unloaded in an empty Vim')
  let l:jieba_autocmds = execute('autocmd onesimus_jieba')
  call assert_equal(-1, match(l:jieba_autocmds,
        \ '\<\%(CursorMovedI\|TextChangedI\)\>'),
        \ 'jieba never performs its first synchronous load inside Insert mode')
  if has('python3') && has_key(g:plugs, 'jieba.vim')
    call assert_match('InsertLeave', l:jieba_autocmds,
          \ 'typed Han text activates jieba immediately after leaving Insert mode')
  endif

  execute 'edit '.fnameescape($VIMRCDIR.'/README.md')
  doautocmd <nomodeline> BufReadPost
  call assert_equal(1, get(b:, 'editorconfig_applied', 0),
        \ 'named project files use EditorConfig on every supported Vim')
  call assert_equal(2, &l:shiftwidth)
  setlocal shiftwidth=6
  call OnesimusConfigureIndentGuides()
  call assert_match('\%(leadmultispace\|multispace\):│     ', &l:listchars,
        \ 'the fixture starts with six-column indentation markers')
  doautocmd <nomodeline> BufReadPost
  call assert_equal(2, &l:shiftwidth)
  call assert_match('\%(leadmultispace\|multispace\):│ ', &l:listchars,
        \ 'EditorConfig rebuilds markers for its effective indent size')

  enew
  call setline(1, 'An ASCII-only Markdown buffer.')
  setfiletype markdown
  call assert_false(exists('g:loaded_jieba_vim'),
        \ 'ASCII Markdown keeps the jieba bridge unloaded')
  call assert_equal('expr', &l:foldmethod)
  call assert_equal('MarkdownFold()', &l:foldexpr)

  enew
  call setline(1, '中文排版測試。')
  setfiletype markdown
  call assert_true(stridx(&l:formatoptions, 'm') >= 0)
  call assert_true(stridx(&l:formatoptions, 'M') >= 0)
  call assert_true(&l:wrap)
  call assert_true(&l:linebreak)
  call assert_true(&l:breakindent)
  call assert_equal('list:-1', &l:breakindentopt)
  call assert_equal("「\r」", b:surround_113)
  call assert_equal("『\r』", b:surround_81)
  call setline(1, '「中文」')
  normal! gg0%
  call assert_equal('」', strpart(getline('.'), col('.') - 1, 3),
        \ '% matches common full-width CJK pairs')
  call assert_equal(1, g:jieba_vim_lazy)
  call assert_equal(0, g:jieba_vim_keymap)
  if has('python3')
    call assert_true(OnesimusJiebaReady())
    call assert_equal('<Plug>(Jieba_w)', maparg('w', 'n'))
  else
    call assert_false(OnesimusJiebaReady())
    call assert_equal('', maparg('w', 'n'),
          \ 'Vim without +python3 keeps native word motions')
  endif

  let l:undo_cjk = b:undo_ftplugin
  setlocal formatoptions-=mM nowrap nolinebreak nobreakindent
  execute 'source '.fnameescape($VIMRCDIR.'/plugconf/CJK.vim')
  call assert_true(stridx(&l:formatoptions, 'm') >= 0)
  call assert_true(stridx(&l:formatoptions, 'M') >= 0)
  call assert_true(&l:wrap && &l:linebreak && &l:breakindent)
  call assert_equal(l:undo_cjk, b:undo_ftplugin,
        \ 'reloading does not duplicate undo_ftplugin')

  call setline(1, ['中文', '排版'])
  normal! ggJ
  call assert_equal('中文排版', getline(1), 'J avoids a space in CJK text')

  call setline(1, '中文')
  normal! gg0
  call feedkeys('ysiwq', 'xt')
  call assert_equal('「中文」', getline(1), 'q creates Chinese corner quotes')

  let v:errmsg = ''
  silent OnesimusReload
  call assert_notmatch('E127:', v:errmsg,
        \ 'reload must not redefine its active implementation')
  call assert_equal(2, exists(':OnesimusStats'))

  enew
  let l:rainbow_dir = g:plugs.rainbow.dir
  let g:plugs.rainbow.dir = '/tmp/onesimus-plugin-not-installed'
  set filetype=lisp
  call assert_false(exists('b:rainbow_confs'),
        \ 'a missing first-run plugin leaves native matching alone')
  silent OnesimusReload
  call assert_true(exists('b:rainbow_confs'),
        \ 'reload configures an already-open Lisp buffer after installation')
  call assert_equal(l:rainbow_dir, g:plugs.rainbow.dir)
  set filetype=python
  call assert_false(exists('b:rainbow_confs'),
        \ 'leaving an automatically configured Lisp buffer clears rainbow')
  set filetype=lisp
  call assert_true(exists('b:rainbow_confs'),
        \ 'returning to Lisp enables rather than toggles rainbow off')

  let l:nerdtree_dir = g:plugs.nerdtree.dir
  let g:plugs.nerdtree.dir = '/tmp/onesimus-plugin-not-installed'
  let v:errmsg = ''
  silent OnesimusTree
  call assert_notmatch('E492:', v:errmsg,
        \ 'a missing lazy plugin gets a first-run hint, not a raw command error')
  let g:plugs.nerdtree.dir = l:nerdtree_dir

  let l:clap_dir = g:plugs['vim-clap'].dir
  let g:plugs['vim-clap'].dir = '/tmp/onesimus-plugin-not-installed'
  let v:errmsg = ''
  silent OnesimusClap files
  call assert_notmatch('E492:', v:errmsg,
        \ 'the picker facade validates its lazy plugin directory')
  let g:plugs['vim-clap'].dir = l:clap_dir

  call writefile(v:errors, '/tmp/onesimus-smoke-errors')
  if empty(v:errors)
    qall!
  endif
  cquit
endfunction

augroup onesimus_smoke
  autocmd!
  autocmd VimEnter * call <SID>RunSmokeTests()
augroup END
