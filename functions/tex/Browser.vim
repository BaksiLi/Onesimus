" Onesimus keeps its public actions; WebPreview.vim owns the reader session.
function! OnesimusTexBrowser(pdf, main, ...) abort
  return call('webpreview#tex#open', [a:pdf, a:main] + a:000)
endfunction

function! OnesimusTexBrowserFollow(pdf, main, position) abort
  return webpreview#tex#follow(a:pdf, a:main, a:position)
endfunction

function! OnesimusTexBrowserStop() abort
  return webpreview#tex#stop()
endfunction
