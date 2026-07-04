" =================================================================
" [C/C++전용 Vim 설정] 플러그인 + 테마 + C/GDB/Valgrind
" =================================================================

" ================================
" 1. 기본 설정
" ================================
set nocompatible
set encoding=utf-8
set fileencodings=utf-8,cp949
scriptencoding utf-8
set ttimeout
set ttimeoutlen=40

" gf 명령어가 시스템 include 폴더에 있는 라이브러리를 찾음
" 확장자가 없는 단어도 파일 이름으로 인식하도록 허용
set isfname+=~,*,?,[,],-
set path=.,/usr/include/c++/*,/usr/include,/usr/local/include,/Library/Developer/CommandLineTools/usr/include/c++/v1,,
set suffixesadd=.h,.c,.cc,.C,.cpp,.hpp

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

call plug#end()

" ================================
" 3. UI / 테마
" ================================
syntax on
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

" coc.nvim 팝업창 가독성 개선
highlight CocFloating      ctermbg=235 guibg=#3c3836
highlight CocErrorFloat    ctermfg=203 guifg=#fb4934
highlight CocInfoFloat     ctermfg=214 guifg=#fabd2f
highlight CocWarningFloat  ctermfg=208 guifg=#fe8019
highlight CocDisabled ctermfg=242 guifg=#665c54
highlight CocHintFloat ctermfg=250 guifg=#d5c4a1
highlight CocFadeOut ctermfg=250 guifg=#a89984
highlight CocUnusedSuggest ctermfg=250 guifg=#a89984

set autoindent
set smartindent
set tabstop=4
set shiftwidth=4
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
let g:cpp_experimental_template_highlight = 1 " 템플릿 하이라이트 활성화

" 복잡한 템플릿 구조(<>, ::) 안에서 괄호 짝을 잘 찾기 위한 매치 매핑 강화
runtime macros/matchit.vim

" ================================
" 5. 실행 관련 헬퍼 함수
" ================================
function! s:ExeName()
    return 'build/' . expand('%:r')
endfunction

function! s:IsCppFile()
    let ext = expand('%:e')
    return ext ==# 'c' || ext ==# 'cpp' || ext ==# 'cc' || ext ==# 'hpp' || ext ==# 'h'
endfunction

function! s:GetCompiler()
    return expand('%:e') ==# 'c' ? 'gcc' : 'g++'
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
" 6. Build
" ================================
function! s:Build()
    if !s:IsCppFile()
        echo "C/C++ 파일이 아님"
        return ''
    endif

    if !isdirectory('build')
        call mkdir('build', 'p')
    endif

    let bin = s:GetCompiler()
    let exe = s:ExeName()
    let ext = expand('%:e')

    if ext ==# 'c'
        let files = glob('*.c', 0, 1)
    else
        let files = glob('*.cpp', 0, 1) + glob('*.cc', 0, 1) + glob('*.cxx', 0, 1)
    endif

    let has_raylib = filereadable('raylib.h')
    if !has_raylib
        for f in files
            if join(readfile(f, '', 30), "\n") =~# 'raylib\.h'
                let has_raylib = 1
                break
            endif
        endfor
    endif

    " [수정] C++ 템플릿 디버깅을 위해 -ftemplate-backtrace-limit 설정 추가
    " 템플릿 에러가 깊어질 때 생략되는 것을 방지하기 위해 단계를 늘리거나(예: 100) 0(무제한)으로 설정
    if ext ==# 'c'
        let cmd_list = [bin, '-g', '-Wall', '-Wextra']
    else
        let cmd_list = [bin, '-g', '-std=c++23', '-Wall', '-Wextra', '-Wconversion', '-Wsign-conversion', '-ftemplate-backtrace-limit=0']
    endif

    " cmd_list에 들어가는 파일명들에 shellescape()를 중복으로 적용하지 않고 순수 리스트로 병합
    call extend(cmd_list, copy(files))
    call extend(cmd_list, ['-o', exe])

    if has_raylib
        call extend(cmd_list, ['-lraylib', '-lGL', '-lm', '-lpthread', '-ldl', '-lrt', '-lX11'])
    endif

    " [개선] execute '!' 대신 비동기성이 확보되거나 화면 깨짐이 적은 구조로 명령어를 결합
    " 이스케이프 꼬임을 막기 위해 각 인자를 쉘 인자로 안전하게 결합하여 가공
    let safe_cmd = join(map(cmd_list, 'shellescape(v:val)'), ' ')
    
    echo "컴파일 중..."
    execute '!' . safe_cmd

    if v:shell_error != 0
        redraw!
        echo "컴파일 실패"
        return ''
    endif

    redraw!
    echo "컴파일 성공: " . exe
    return exe
endfunction

" ================================
" 7. 실행
" ================================
function! s:Run()
    let exe = s:Build()
    if exe == '' | return | endif

    execute '!./' . shellescape(exe)
endfunction

" ================================
" 8. Valgrind
" ================================
function! s:Valgrind(type)
    let exe = s:Build()
    if exe == '' | return | endif

    if a:type ==# 'full'
        execute '!valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes ./' . shellescape(exe)
    else
        execute '!valgrind --leak-check=full ./' . shellescape(exe)
    endif
endfunction

" ================================
" 9. GDB
" ================================
function! s:GdbExitHandler(job_id, data, event)
    echo "GDB 종료"
endfunction

function! s:GDB()
    let exe = s:Build()
    if exe == '' | return | endif

    botright 12split
    " term_start 리스트 인자 사용 시 shellescape를 해제하여 경로 인식 차단 현상 방지
    let buf = term_start(['gdb', '-q', exe], {
        \ 'exit_cb': function('s:GdbExitHandler'),
        \ 'curwin': 1,
        \ 'term_name': 'gdb-inferior'
        \ })

    " feedkeys 대신 고유 버퍼 ID에 타이밍 유실 없이 직동 제어 키 송신
    call term_sendkeys(buf, "break main\nrun\n")
endfunction

" ================================
" 10. 단축키 설정
" ================================
let mapleader=" "

nnoremap <F5> :w<CR>:call <SID>Run()<CR>
nnoremap <F6> :w<CR>:call <SID>Build()<CR>
nnoremap <F7> :w<CR>:call <SID>Valgrind('basic')<CR>
nnoremap <F8> :w<CR>:call <SID>Valgrind('full')<CR>
nnoremap <leader>d :w<CR>:call <SID>GDB()<CR>
nnoremap <silent> K :call CocActionAsync('doHover')<CR>

" LSP 기반 코드 탐색 단축키
nnoremap <silent> gd <Plug>(coc-definition)   
nnoremap <silent> gy <Plug>(coc-type-definition)
nnoremap <silent> gi <Plug>(coc-implementation)
nnoremap <silent> gr <Plug>(coc-references)

" GDB 내부 제어 (비동기 및 입력 복귀 보정 버전)
tnoremap <F10> <C-\><C-n>:call term_sendkeys(bufnr('%'), "next\n")<CR>i
tnoremap <F11> <C-\><C-n>:call term_sendkeys(bufnr('%'), "step\n")<CR>i
tnoremap <F12> <C-\><C-n>:call term_sendkeys(bufnr('%'), "continue\n")<CR>i

" 코드창 연동 기능: 코드 편집 중에 <leader>b를 누르면 활성화된 GDB 세션으로 중단점 직접 전송
nnoremap <leader>b :call <SID>SendGdbCommand("break " . expand('%:p') . ":" . line('.'))<CR>

" ================================
" 11. 기타 단축키
" ================================
nnoremap <C-n> :NERDTreeToggle<CR>
nnoremap <C-p> :Files<CR>
nnoremap <leader>f :Rg<CR>

inoremap jk <Esc>
inoremap kj <Esc>

" coc.nvim 공식 추천 가독성 및 안전성 최적화 엔터/탭 매핑
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm()
                              \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

" ================================
" 12. WSL 클립보드 연동
" ================================
let g:clipboard = {
    \ 'name': 'win32yank',
    \ 'copy': { '+': 'win32yank.exe -i --crlf', '*': 'win32yank.exe -i --crlf' },
    \ 'paste': { '+': 'win32yank.exe -o --lf', '*': 'win32yank.exe -o --lf' },
    \ 'cache_enabled': 0,
    \ }

" ================================
" 13. 커서 모양 고정 (WSL 윈도우 터미널 가비지 방지)
" ================================
if !has('gui_running')
  " 입력 모드로 들어갈 때: 얇은 바 (5 q)
  let &t_SI = "\<Esc>[5 q"
  " 입력 모드에서 나갈 때 (일반 모드): 블록 (2 q)
  let &t_EI = "\<Esc>[2 q"
  " 교체 모드 (Replace): 밑줄 (3 q)
  let &t_SR = "\<Esc>[3 q"
endif

