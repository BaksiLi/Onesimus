" The TeX module (functions/tex/) loads with the first TeX buffer, so other
" sessions never pay for it.  It drives VimTeX, which a core Vim lacks.
" This runs before VimTeX's own ftplugin (the root heads 'runtimepath'), so
" the module is ready when VimtexEventInitPost fires.
if get(g:, 'onesimus_core', 0) || exists('g:onesimus_tex_module')
  finish
endif
let g:onesimus_tex_module = 1
SourceAll $VIMRCDIR.'/functions/tex'
