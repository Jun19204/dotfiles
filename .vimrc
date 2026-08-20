" =================================================================
" [C/C++전용 Vim 설정] 플러그인 + 테마 + CMake/GDB/Valgrind
" =================================================================

" ================================
" 1. 기본 설정 및 편집 옵션
" ================================
set nocompatible
set encoding=utf-8
set fileencodings=utf-8,cp949
scriptencoding utf-8
set ttimeout
set ttimeoutlen=40

" gf 명령어가 시스템 include 폴더에 있는 라이브러리를 찾음
set isfname+=~,*,?,[,],-
set path=.,/usr/include/c++/*,/usr/include,/usr/local/include,/Library/Developer/CommandLineTools/usr/include/c++/v1,,
set suffixesadd=.h,.c,.cc,.C,.cpp,.hpp

" 검색 및 분할창 편의 옵션
set ignorecase
set smartcase
set autoread
set splitbelow
set splitright

" ================================
" 2. 플러그인 (vim-plug)
" ================================
call plug#begin('~/.vim/plugged')

Plug 'preservim/nerdtree'
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'vim-airline/vim-airline'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'octol/vim-cpp-enhanced-highlight'
Plug 'Yggdroot/indentLine'
Plug 'morhetz/gruvbox'
Plug 'frazrepo/vim-rainbow'
Plug 'derekwyatt/vim-fswitch' " C/C++ 헤더-소스 파일 고속 전환
Plug 'pboettch/vim-cmake-syntax' " CMake 전용 구문 강조

" coc.nvim 기본 시맨틱 하이라이팅 간섭 방지 (plug#end() 이전에 설정되어야 적용됨)
let g:coc_default_semantic_highlight_groups = 0

call plug#end()

" ================================
" 3. UI / 테마 & 파일타입 설정
" ================================
filetype plugin indent on
syntax on

" CMake 파일 타입 감지 및 하이라이트 동기화
autocmd BufNewFile,BufRead CMakeLists.txt,*.cmake setlocal filetype=cmake
autocmd FileType cmake syntax on

" CMake 명령어(set, enable_testing, add_executable 등) 색상을 문자열("") 색상과 동일하게 설정
autocmd FileType cmake highlight link cmakeCommand String
autocmd FileType cmake highlight link cmakeStatement String
autocmd FileType cmake highlight link cmakeCommandStart String

set number
set termguicolors
set background=dark
let g:gruvbox_contrast_dark = 'medium'
let g:gruvbox_bold = 0
let g:gruvbox_italic = 0
let g:airline_theme='gruvbox'
let g:airline_powerline_fonts = 0
let g:rainbow_active = 1
colorscheme gruvbox

set cursorline
highlight CursorLine guibg=#2a2a2a
highlight ColorColumn guibg=#1f1f1f

" indentLine Gruvbox 가독성 최적화
let g:indentLine_char = '┊'
let g:indentLine_color_gui = '#504945'

" coc.nvim 팝업창 가독성 개선
highlight CocFloating       ctermbg=235 guibg=#3c3836
highlight CocErrorFloat      ctermfg=203 guifg=#fb4934
highlight CocInfoFloat       ctermfg=214 guifg=#fabd2f
highlight CocWarningFloat    ctermfg=208 guifg=#fe8019
highlight CocDisabled       ctermfg=242 guifg=#665c54
highlight CocHintFloat       ctermfg=250 guifg=#d5c4a1
highlight CocFadeOut         ctermfg=250 guifg=#a89984
highlight CocUnusedSuggest   ctermfg=250 guifg=#a89984

set autoindent
set smartindent
set tabstop=2
set shiftwidth=2
set expandtab
set completeopt=menuone,noinsert,noselect
set clipboard=unnamedplus
set signcolumn=yes
set colorcolumn=100

" ================================
" 4. C++ 하이라이트
" ================================
let g:cpp_class_scope_highlight = 1
let g:cpp_member_variable_highlight = 1
let g:cpp_class_decl_highlight = 1
let g:cpp_experimental_template_highlight = 1

runtime macros/matchit.vim

" ================================
" 5. CMake 타겟 자동 추적 헬퍼
" ================================
function! s:GetCMakeExe()
  let l:dir = expand('%:p:h:t')
  let l:exe_path = 'build/' . l:dir . '/' . l:dir . '_exe'

  if !filereadable(l:exe_path)
    let l:found = glob('build/' . l:dir . '/*', 0, 1)
    let l:executable = filter(l:found, 'executable(v:val) && v:val !~# "\.so$" && v:val !~# "\.a$"')
    return !empty(l:executable) ? l:executable[0] : ''
  endif

  return l:exe_path
endfunction

function! s:SendGdbCommand(cmd)
  let buf = filter(range(1, bufnr('$')), 'bufname(v:val) =~# "gdb-inferior"')
  if !empty(buf)
    call term_sendkeys(buf[0], a:cmd . "\n")
    echo "GDB 명령 전송: " . a:cmd
  else
    echo "실행 중인 GDB 터미널을 찾을 수 없습니다."
  endif
endfunction

" ================================
" 6. CMake 빌드
" ================================
function! s:CMakeBuild()
  if !isdirectory('build')
    call mkdir('build', 'p')
  endif

  echo "CMake Configure & Build 중..."
  let l:cmd = 'cmake -B build -DCMAKE_BUILD_TYPE=Debug && cmake --build build'
  execute '!' . l:cmd

  if v:shell_error != 0
    redraw!
    echo "CMake 빌드 실패"
    return 0
  endif

  " coc.nvim/clangd 자동완성용 심볼릭 링크 자동 생성
  if filereadable('build/compile_commands.json') && !filereadable('compile_commands.json')
    call system('ln -s build/compile_commands.json .')
  endif

  redraw!
  echo "CMake 빌드 성공"
  return 1
endfunction

" ================================
" 7. CMake 실행
" ================================
function! s:CMakeRun()
  if s:CMakeBuild()
    let l:exe = s:GetCMakeExe()
    if l:exe ==# ''
      echo "실행 가능한 바이너리를 찾을 수 없습니다."
      return
    endif
    execute '!' . shellescape(l:exe)
  endif
endfunction

" ================================
" 8. Valgrind 메모리 검사
" ================================
function! s:CMakeValgrind(type)
  if s:CMakeBuild()
    let l:exe = s:GetCMakeExe()
    if l:exe ==# ''
      echo "실행 가능한 바이너리를 찾을 수 없습니다."
      return
    endif

    if a:type ==# 'full'
      execute '!valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes ' . shellescape(l:exe)
    else
      execute '!valgrind --leak-check=full ' . shellescape(l:exe)
    endif
  endif
endfunction

" ================================
" 9. GDB 디버깅
" ================================
function! s:GdbExitHandler(job_id, data, event)
  echo "GDB 종료"
endfunction

function! s:CMakeGDB()
  if s:CMakeBuild()
    let l:exe = s:GetCMakeExe()
    if l:exe ==# ''
      echo "실행 가능한 바이너리를 찾을 수 없습니다."
      return
    endif

    botright 12split
    let l:buf = term_start(['gdb', '-q', l:exe], {
          \ 'exit_cb': function('<SID>GdbExitHandler'),
          \ 'curwin': 1,
          \ 'term_name': 'gdb-inferior'
          \ })

    call term_sendkeys(l:buf, "break main\nrun\n")
  endif
endfunction

" ================================
" 10. 단축키 설정
" ================================
let mapleader=" "

" F1 키로 Inlay Hints 즉시 토글 (CocRestart 없이 내장 토글 기능 사용)
nnoremap <F1> :CocCommand document.toggleInlayHint<CR>

" F4: 헤더/소스 파일(.h <-> .cpp) 즉시 전환
nnoremap <F4> :FSHere<CR>

" CMake 기반 빌드/실행/Valgrind/GDB 단축키
nnoremap <F5> :w<CR>:call <SID>CMakeRun()<CR>
nnoremap <F6> :w<CR>:call <SID>CMakeBuild()<CR>
nnoremap <F7> :w<CR>:call <SID>CMakeValgrind('basic')<CR>
nnoremap <F8> :w<CR>:call <SID>CMakeValgrind('full')<CR>
nnoremap <leader>d :w<CR>:call <SID>CMakeGDB()<CR>
nnoremap <silent> K :call CocActionAsync('doHover')<CR>

" LSP 기반 코드 탐색 단축키
nnoremap <silent> gd <Plug>(coc-definition)
nnoremap <silent> gy <Plug>(coc-type-definition)
nnoremap <silent> gi <Plug>(coc-implementation)
nnoremap <silent> gr <Plug>(coc-references)
nnoremap <leader>rn <Plug>(coc-rename)

" 전체 코드 LSP/clang-format 정렬 (Space + c + f)
" Format Provider가 없는 경우 일반 gg=G 로 fallback 처리
nnoremap <silent> <leader>cf :call FormatCode()<CR>

function! FormatCode()
  if CocHasProvider('format')
    call CocAction('format')
  else
    normal! gg=G
    echo "LSP Formatter 미연동: 일반 gg=G 정렬 적용"
  endif
endfunction

" GDB 내부 제어
tnoremap <F10> <C-\><C-n>:call term_sendkeys(bufnr('%'), "next\n")<CR>i
tnoremap <F11> <C-\><C-n>:call term_sendkeys(bufnr('%'), "step\n")<CR>i
tnoremap <F12> <C-\><C-n>:call term_sendkeys(bufnr('%'), "continue\n")<CR>i

" 코드창 연동: 현재 줄에 Breakpoint 지정
nnoremap <leader>b :call <SID>SendGdbCommand("break " . expand('%:p') . ":" . line('.'))<CR>

" 검색 하이라이트 해제 (ESC 2번)
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

" ================================
" 11. 기타 단축키 및 completion 최적화
" ================================
nnoremap <C-n> :NERDTreeToggle<CR>
nnoremap <C-p> :Files<CR>
nnoremap <leader>f :Rg<CR>

inoremap jk <Esc>
inoremap kj <Esc>

" coc.nvim 추천 자동완성 매핑
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm()
      \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"
inoremap <silent><expr> <Tab> coc#pum#visible() ? coc#pum#next(1) : "\<Tab>"
inoremap <silent><expr> <S-Tab> coc#pum#visible() ? coc#pum#prev(1) : "\<S-Tab>"

" ================================
" 12. vim-fswitch 세부 경로 설정
" ================================
" .cpp 파일에서 .h 파일을 찾을 경로 지정 (include, ../include 등)
au BufEnter *.cpp,*.cc,*.c let b:fswitchdst = 'h,hpp' | let b:fswitchlocs = 'reg:|src|include|,reg:|src|../include|,../include,.'
" .h 파일에서 .cpp 파일을 찾을 경로 지정 (src, ../src 등)
au BufEnter *.h,*.hpp let b:fswitchdst = 'cpp,cc,c' | let b:fswitchlocs = 'reg:|include|src|,reg:|include|../src|,../src,.'

" ================================
" 13. WSL 클립보드 연동
" ================================
let g:clipboard = {
      \ 'name': 'win32yank',
      \ 'copy': { '+': 'win32yank.exe -i --crlf', '*': 'win32yank.exe -i --crlf' },
      \ 'paste': { '+': 'win32yank.exe -o --lf', '*': 'win32yank.exe -o --lf' },
      \ 'cache_enabled': 0,
      \ }

" ================================
" 14. 커서 모양 고정 (WSL 윈도우 터미널 가비지 방지)
" ================================
if !has('gui_running')
  let &t_SI = "\<Esc>[5 q"
  let &t_EI = "\<Esc>[2 q"
  let &t_SR = "\<Esc>[3 q"
endif

