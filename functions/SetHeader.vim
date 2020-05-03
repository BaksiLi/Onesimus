func SetHeader()
  if &filetype ==? 'sh'
    call setline(1,"\#!/bin/bash")
    call append(line("."), "")
    elseif &filetype ==? 'python'
        call setline(1,"#!/usr/bin/env python")
        call append(line("."),"# -*- coding: utf-8 -*-")
      call append(line(".")+1, "")
    elseif &filetype ==? 'ruby'
        call setline(1,"#!/usr/bin/env ruby")
        call append(line("."),"# encoding: utf-8")
      call append(line(".")+1, "")
    elseif &filetype ==? 'typescript'
        call setline(1,"author Baksi")  " arbitrary

"    elseif &filetype ==? 'mkd'
"        call setline(1,"<head><meta charset=\"UTF-8\"></head>")
  endif
  if expand("%:e") ==? 'cpp'
    call append(line(".")+6, "#include<iostream>")
    call append(line(".")+7, "using namespace std;")
    call append(line(".")+8, "")
  endif
  if &filetype ==? 'c'
    call append(line(".")+6, "#include<stdio.h>")
    call append(line(".")+7, "")
  endif
  if expand("%:e") ==? 'h'
    call append(line(".")+6, "#ifndef _".toupper(expand("%:r"))."_H")
    call append(line(".")+7, "#define _".toupper(expand("%:r"))."_H")
    call append(line(".")+8, "#endif")
  endif
  if &filetype ==? 'java'
    call append(line(".")+6,"public class ".expand("%:r"))
    call append(line(".")+7,"")
  endif
  " go to the last line
  exec 'normal G'
endfunc


