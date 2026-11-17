if exists('g:loaded_webpreview') || v:version < 802
  finish
endif
let g:loaded_webpreview = 1

command! WebPreview call webpreview#open()
command! -nargs=? -complete=file WebPreviewChanges call webpreview#tex#current(<q-args>)
command! WebPreviewInquiry call webpreview#inquiry()
command! WebPreviewStop call webpreview#stop()
call webpreview#setup()
