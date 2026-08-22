" =================================================================
" C/C++ 전용 Vim 설정
" C++20/23 + CMake / CTest / GTest / GDB / ASan / Valgrind
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
" gf 명령어가 시스템 include 폴더의 라이브러리를 찾도록 설정
set isfname+=~,*,?,[,],-
set path=.,/usr/include/c++/*,/usr/include,/usr/local/include,,
set suffixesadd=.h,.c,.cc,.C,.cpp,.hpp
" 검색 및 분할창 편의 옵션
set ignorecase
set smartcase
set autoread
set splitbelow
set splitright

" ================================
" 2. 플러그인
" ================================
call plug#begin('~/.vim/plugged')
Plug 'preservim/nerdtree'
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'vim-airline/vim-airline'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'Yggdroot/indentLine'
Plug 'morhetz/gruvbox'
Plug 'derekwyatt/vim-fswitch'
Plug 'pboettch/vim-cmake-syntax'
" coc.nvim semantic highlighting
let g:coc_default_semantic_highlight_groups = 1
call plug#end()

" ================================
" 3. UI / 테마 / 편집 설정
" ================================
filetype plugin indent on
syntax on

set number
set cursorline
set termguicolors
set background=dark

let g:gruvbox_contrast_dark = 'medium'
let g:gruvbox_bold = 0
let g:gruvbox_italic = 0
let g:airline_theme = 'gruvbox'
let g:airline_powerline_fonts = 0
let g:vim_json_conceal = 0
set conceallevel=0

colorscheme gruvbox
augroup CustomHighlights
  autocmd!
  autocmd ColorScheme gruvbox highlight CursorLine guibg=#2a2a2a
  autocmd ColorScheme gruvbox highlight ColorColumn guibg=#1f1f1f
  autocmd ColorScheme gruvbox highlight CocFloating ctermbg=235 guibg=#3c3836
  autocmd ColorScheme gruvbox highlight CocErrorFloat ctermfg=203 guifg=#fb4934
  autocmd ColorScheme gruvbox highlight CocInfoFloat ctermfg=214 guifg=#fabd2f
  autocmd ColorScheme gruvbox highlight CocWarningFloat ctermfg=208 guifg=#fe8019
  autocmd ColorScheme gruvbox highlight CocDisabled ctermfg=242 guifg=#665c54
  autocmd ColorScheme gruvbox highlight CocHintFloat ctermfg=250 guifg=#d5c4a1
  autocmd ColorScheme gruvbox highlight CocFadeOut ctermfg=250 guifg=#a89984
  autocmd ColorScheme gruvbox highlight CocUnusedSuggest ctermfg=250 guifg=#a89984
augroup END

let g:indentLine_char = '┊'
let g:indentLine_color_gui = '#504945'

set autoindent
set cindent
set tabstop=2
set shiftwidth=2
set expandtab
set completeopt=noinsert,menuone
set clipboard=unnamedplus
set signcolumn=yes
set colorcolumn=100

" ================================
" 4. CMake / GTest / GDB 헬퍼
" ================================
" GDB 터미널 버퍼 ID 추적용 변수
let s:gdb_bufnr = -1

" -------------------------------------------------
" 일반 실행 파일 추적
" *_test 바이너리는 제외
" -------------------------------------------------
function! s:GetCMakeExe()
  if !isdirectory('build')
    return ''
  endif
  let l:all_files = glob('build/**/*', 0, 1)
  let l:executables = filter(
        \ l:all_files,
        \ 'filereadable(v:val) && executable(v:val) && ' .
        \ 'v:val !~# "\.\\(so\\|a\\|o\\|cmake\\|check\\|json\\|ninja\\|txt\\|log\\|make\\|internal\\|marks\\)$" && ' .
        \ 'v:val !~# "/CMakeFiles/" && ' .
        \ 'v:val !~# "_test$"'
        \ )
  if empty(l:executables)
    return ''
  endif
  if len(l:executables) == 1
    return l:executables[0]
  endif
  " 가장 최근 수정된 실행 파일 선택
  let l:latest_exe = l:executables[0]
  let l:max_mtime = getftime(l:latest_exe)
  for l:exe in l:executables
    let l:mtime = getftime(l:exe)
    if l:mtime > l:max_mtime
      let l:max_mtime = l:mtime
      let l:latest_exe = l:exe
    endif
  endfor
  return l:latest_exe
endfunction

" -------------------------------------------------
" GTest 바이너리 추적
" *_test
" -------------------------------------------------
function! s:GetGTestExe()
  if !isdirectory('build')
    return ''
  endif
  let l:module = expand('%:p:h:t')
  if l:module ==# 'tests'
    let l:module = expand('%:p:h:h:t')
  endif
  " 현재 모듈 테스트 우선
  let l:target_test = glob(
        \ 'build/**/' . l:module . '_test',
        \ 0,
        \ 1
        \ )
  if !empty(l:target_test) && executable(l:target_test[0])
    return l:target_test[0]
  endif
  let l:all_tests = filter(
        \ glob('build/**/*', 0, 1),
        \ 'filereadable(v:val) && executable(v:val) && v:val =~# "_test$"'
        \ )
  if empty(l:all_tests)
    return ''
  endif
  let l:latest_test = l:all_tests[0]
  let l:max_mtime = getftime(l:latest_test)
  for l:test in l:all_tests
    let l:mtime = getftime(l:test)
    if l:mtime > l:max_mtime
      let l:max_mtime = l:mtime
      let l:latest_test = l:test
    endif
  endfor
  return l:latest_test
endfunction

" -------------------------------------------------
" 현재 Vim이 관리하는 build 모드
"
" asan
" valgrind
"
" build/.vim_build_mode
" -------------------------------------------------
function! s:GetBuildMode()
  let l:mode_file = 'build/.vim_build_mode'
  if !filereadable(l:mode_file)
    return ''
  endif
  let l:mode = readfile(l:mode_file)
  if empty(l:mode)
    return ''
  endif
  return l:mode[0]
endfunction

function! s:SetBuildMode(mode)
  if !isdirectory('build')
    call mkdir('build', 'p')
  endif
  call writefile(
        \ [a:mode],
        \ 'build/.vim_build_mode'
        \ )
endfunction

" -------------------------------------------------
" 실행 중인 GDB 터미널에 명령 전달 (버퍼 번호 기반)
" -------------------------------------------------
function! s:SendGdbCommand(cmd)
  if s:gdb_bufnr != -1 && bufexists(s:gdb_bufnr)
    call term_sendkeys(
          \ s:gdb_bufnr,
          \ a:cmd . "\n"
          \ )
  else
    echo "실행 중인 GDB 터미널을 찾을 수 없습니다."
  endif
endfunction

" ================================
" 5. CMake Build
" ================================
" -------------------------------------------------
" use_sanitizer = 1
"   USE_SANITIZER=ON
"   build mode = asan
"
" use_sanitizer = 0
"   USE_SANITIZER=OFF
"   build mode = valgrind
" -------------------------------------------------
function! s:CMakeBuild(use_sanitizer)
  if !isdirectory('build')
    call mkdir('build', 'p')
  endif
  let l:san_flag =
        \ a:use_sanitizer
        \ ? '-DUSE_SANITIZER=ON'
        \ : '-DUSE_SANITIZER=OFF'
  let l:build_mode =
        \ a:use_sanitizer
        \ ? 'asan'
        \ : 'valgrind'
  echo "CMake Configure & Build 중... (" .
        \ (a:use_sanitizer
        \ ? "ASan ON"
        \ : "ASan OFF / Valgrind용")
        \ . ")"
  let l:cmd =
        \ 'cmake -B build ' .
        \ '-DCMAKE_BUILD_TYPE=Debug ' .
        \ '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON ' .
        \ l:san_flag .
        \ ' && cmake --build build'
  execute '!' . l:cmd
  if v:shell_error != 0
    redraw!
    echo "CMake 빌드 실패"
    return 0
  endif
  " 빌드 성공한 경우에만 상태 기록
  call s:SetBuildMode(l:build_mode)
  " clangd용 compile_commands.json 강제 덮어쓰기 링크 (ln -sf 사용)
  if filereadable('build/compile_commands.json')
    call system(
          \ 'ln -sf build/compile_commands.json .'
          \ )
  endif
  redraw!
  echo "CMake 빌드 성공: " . l:build_mode
  return 1
endfunction

" ================================
" 6. 실행 / ASan / Valgrind
" ================================
" -------------------------------------------------
" F6
" ASan Build & Run
" -------------------------------------------------
function! s:CMakeASanRun()
  if !s:CMakeBuild(1)
    return
  endif
  let l:exe = s:GetCMakeExe()
  if l:exe ==# ''
    echo "실행 바이너리를 찾을 수 없습니다."
    return
  endif
  execute '!' . shellescape(l:exe)
endfunction

" -------------------------------------------------
" F9
" Valgrind 실행
"
" build/.vim_build_mode가
" valgrind가 아니면 자동 ASan OFF 빌드
" -------------------------------------------------
function! s:CMakeValgrindRun()
  let l:build_mode = s:GetBuildMode()
  let l:exe = s:GetCMakeExe()
  " 현재 build가 Valgrind용이 아니면 재빌드
  if l:build_mode !=# 'valgrind'
    if l:build_mode ==# 'asan'
      echo "현재 build는 ASan ON 상태입니다."
      echo "Valgrind용 ASan OFF 재빌드를 수행합니다..."
    else
      echo "빌드 모드를 확인할 수 없습니다."
      echo "Valgrind용 ASan OFF 빌드를 수행합니다..."
    endif
    if !s:CMakeBuild(0)
      return
    endif
    let l:exe = s:GetCMakeExe()
  endif
  " Valgrind 상태이지만 실행 파일이 없는 경우
  if l:exe ==# '' || !filereadable(l:exe)
    echo "실행 파일을 찾을 수 없습니다."
    echo "Valgrind용 빌드를 다시 수행합니다..."
    if !s:CMakeBuild(0)
      return
    endif
    let l:exe = s:GetCMakeExe()
  endif
  if l:exe ==# ''
    echo "실행 바이너리를 찾을 수 없습니다."
    return
  endif
  echo "Valgrind 상세 메모리 검사 실행..."
  execute '!' . 'valgrind ' .
        \ '--leak-check=full ' .
        \ '--show-leak-kinds=all ' .
        \ '--track-origins=yes ' .
        \ shellescape(l:exe)
endfunction

" ================================
" 7. CTest / GTest
" ================================
function! s:RunCTestAll()
  if !isdirectory('build')
    if !s:CMakeBuild(1)
      return
    endif
  endif
  execute '!ctest --test-dir build --output-on-failure'
endfunction

function! s:RunCTestCurrentModule()
  if !isdirectory('build')
    if !s:CMakeBuild(1)
      return
    endif
  endif
  let l:module = expand('%:p:h:t')
  if l:module ==# 'tests'
    let l:module = expand('%:p:h:h:t')
  endif
  echo "모듈 테스트 실행: " . l:module
  execute
        \ '!ctest --test-dir build -R ' .
        \ shellescape(l:module) .
        \ ' --output-on-failure'
endfunction

function! s:RunGTestDirect()
  if !isdirectory('build')
    if !s:CMakeBuild(1)
      return
    endif
  endif
  let l:test_exe = s:GetGTestExe()
  if l:test_exe ==# ''
    echo "GTest 실행 파일(*_test)을 찾을 수 없습니다."
    return
  endif
  execute '!' . shellescape(l:test_exe)
endfunction

" ================================
" 8. GDB
" ================================
function! s:GdbExitHandler(job_id, data)
  let s:gdb_bufnr = -1
  echo "GDB 종료"
endfunction

function! s:CMakeGDB()
  if !s:CMakeBuild(1)
    return
  endif
  let l:exe = s:GetCMakeExe()
  if l:exe ==# ''
    echo "실행 바이너리를 찾을 수 없습니다."
    return
  endif
  botright 12split
  let s:gdb_bufnr = term_start(
        \ ['gdb', '-q', l:exe],
        \ {
        \   'exit_cb': function('s:GdbExitHandler'),
        \   'curwin': 1,
        \   'term_name': 'gdb-inferior'
        \ }
        \ )
  call term_sendkeys(
        \ s:gdb_bufnr,
        \ "break main\nrun\n"
        \ )
endfunction

" ================================
" 9. 단축키
" ================================
let mapleader = " "

" ----------------
" LSP / 파일 전환
" ----------------
nnoremap <F1> :CocCommand document.toggleInlayHint<CR>
nnoremap <F4> :FSHere<CR>

" ----------------
" Build / Memory
" ----------------
" F5 : ASan Build
" F6 : ASan Build & Run
" F8 : Valgrind용 Build
" F9 : Valgrind Run
nnoremap <F5> :w<CR>:call <SID>CMakeBuild(1)<CR>
nnoremap <F6> :w<CR>:call <SID>CMakeASanRun()<CR>
nnoremap <F8> :w<CR>:call <SID>CMakeBuild(0)<CR>
nnoremap <F9> :w<CR>:call <SID>CMakeValgrindRun()<CR>

" ----------------
" CTest / GTest
" ----------------
" <leader>t : 전체 CTest
" <leader>f : 현재 모듈 CTest
" <leader>g : GTest 직접 실행
nnoremap <leader>t
      \ :w<CR>
      \ :call <SID>RunCTestAll()<CR>
nnoremap <leader>f
      \ :w<CR>
      \ :call <SID>RunCTestCurrentModule()<CR>
nnoremap <leader>g
      \ :w<CR>
      \ :call <SID>RunGTestDirect()<CR>

" ----------------
" GDB
" ----------------
nnoremap <leader>d
      \ :w<CR>
      \ :call <SID>CMakeGDB()<CR>
nnoremap <leader>b
      \ :call <SID>SendGdbCommand(
      \ "break " . expand('%:t') . ":" . line('.')
      \ )<CR>

" ----------------
" CoC / LSP
" ----------------
nnoremap <silent> K
      \ :call CocActionAsync('doHover')<CR>
nnoremap <silent> gd
      \ <Plug>(coc-definition)
nnoremap <silent> gy
      \ <Plug>(coc-type-definition)
nnoremap <silent> gi
      \ <Plug>(coc-implementation)
nnoremap <silent> gr
      \ <Plug>(coc-references)
nnoremap <silent> <leader>rn
      \ <Plug>(coc-rename)

" ----------------
" 코드 포맷
" ----------------
nnoremap <silent> <leader>cf
      \ :call FormatCode()<CR>

function! FormatCode()
  if CocHasProvider('format')
    call CocAction('format')
  else
    normal! gg=G
    echo "LSP Formatter 미연동: 일반 gg=G 정렬 적용"
  endif
endfunction

" ----------------
" GDB Step Control
" ----------------
" F10 : next
" F11 : step
" F12 : continue
tnoremap <F10>
      \ <C-\><C-n>
      \ :call <SID>SendGdbCommand("next")<CR>i
tnoremap <F11>
      \ <C-\><C-n>
      \ :call <SID>SendGdbCommand("step")<CR>i
tnoremap <F12>
      \ <C-\><C-n>
      \ :call <SID>SendGdbCommand("continue")<CR>i
nnoremap <F10>
      \ :call <SID>SendGdbCommand("next")<CR>
nnoremap <F11>
      \ :call <SID>SendGdbCommand("step")<CR>
nnoremap <F12>
      \ :call <SID>SendGdbCommand("continue")<CR>
nnoremap <silent> <Esc><Esc>
      \ :nohlsearch<CR>

" ================================
" 10. 파일 탐색 / 검색
" ================================
" NERDTree
nnoremap <C-n>
      \ :NERDTreeToggle<CR>
" FZF 파일 검색
nnoremap <C-p>
      \ :Files<CR>
" ripgrep + FZF 프로젝트 문자열 검색
nnoremap <leader>rg
      \ :Rg<CR>

" ================================
" 11. Insert Mode
" ================================
inoremap jk <Esc>
inoremap kj <Esc>

" ================================
" 12. coc.nvim Completion
" ================================
function! s:check_back_space() abort
  let l:col = col('.') - 1
  return !l:col || getline('.')[l:col - 1] =~# '\s'
endfunction

inoremap <silent><expr> <CR>
      \ coc#pum#visible()
      \ ? coc#pum#confirm()
      \ : "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"
inoremap <silent><expr> <TAB>
      \ coc#pum#visible()
      \ ? coc#pum#next(1)
      \ : <SID>check_back_space()
      \ ? "\<Tab>"
      \ : coc#refresh()
inoremap <expr> <S-TAB>
      \ coc#pum#visible()
      \ ? coc#pum#prev(1)
      \ : "\<C-h>"

" ================================
" 13. vim-fswitch
" ================================
augroup FSwitchPaths
  autocmd!
  autocmd BufEnter *.cpp,*.cc,*.c
        \ let b:fswitchdst = 'h,hpp' |
        \ let b:fswitchlocs =
        \ 'reg:|src|include|,reg:|src|../include|,../include,.,tests'
  autocmd BufEnter *.h,*.hpp
        \ let b:fswitchdst = 'cpp,cc,c' |
        \ let b:fswitchlocs =
        \ 'reg:|include|src|,reg:|include|../src|,../src,.,tests'
augroup END

" ================================
" 14. WSL 클립보드
" ================================
let g:clipboard = {
      \ 'name': 'win32yank',
      \ 'copy': {
      \   '+': 'win32yank.exe -i --crlf',
      \   '*': 'win32yank.exe -i --crlf'
      \ },
      \ 'paste': {
      \   '+': 'win32yank.exe -o --lf',
      \   '*': 'win32yank.exe -o --lf'
      \ },
      \ 'cache_enabled': 0
      \ }

" ================================
" 15. 커서 모양
" ================================
if !has('gui_running')
  " Insert mode: Vertical Bar
  let &t_SI = "\<Esc>[5 q"
  " Normal mode: Block
  let &t_EI = "\<Esc>[2 q"
  " Replace mode: Underline
  let &t_SR = "\<Esc>[3 q"
endif

