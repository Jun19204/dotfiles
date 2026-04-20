" =================================================================
" [완전 통합 안정본 v2] 플러그인 + 테마 + C/GDB/Valgrind
" =================================================================

" ================================
" 1. 기본 설정
" ================================
set nocompatible
set encoding=utf-8
set fileencodings=utf-8,cp949
scriptencoding utf-8

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

call plug#end()

" ================================
" 3. UI / 테마
" ================================
syntax on
set number
set cursorline
highlight CursorLine guibg=#2a2a2a
highlight ColorColumn guibg=#1f1f1f
set autoindent
set smartindent
set tabstop=4
set shiftwidth=4
set expandtab
set completeopt=menuone,noinsert,noselect
set clipboard=unnamedplus
set signcolumn=yes
set colorcolumn=100

set termguicolors
set background=dark
let g:gruvbox_contrast_dark = 'medium'
let g:gruvbox_bold = 0
let g:gruvbox_italic = 0
let g:airline_theme='gruvbox'
let g:airline_powerline_fonts = 0

colorscheme gruvbox

" ================================
" 4. C++ 하이라이트
" ================================
let g:cpp_class_scope_highlight = 1
let g:cpp_member_variable_highlight = 1
let g:cpp_class_decl_highlight = 1
let g:cpp_experimental_template_highlight = 1

" ================================
" 5. 실행 관련 함수
" ================================

" 실행파일 이름 (경로 분리)
function! s:ExeName()
    return 'build/' . expand('%:r')
endfunction

" C/C++ 파일 확인
function! s:IsCppFile()
    let ext = expand('%:e')
    return ext ==# 'c' || ext ==# 'cpp' || ext ==# 'cc'
endfunction

" 컴파일러 선택
function! s:GetCompiler()
    return expand('%:e') ==# 'c' ? 'gcc' : 'g++'
endfunction

" ================================
" 6. Build (핵심)
" ================================
function! s:Build()
    if !s:IsCppFile()
        echo "C/C++ 파일이 아님"
        return ''
    endif

    " build 디렉토리 생성
    if !isdirectory('build')
        call mkdir('build', 'p')
    endif

    let bin = s:GetCompiler()
    let exe = s:ExeName()

    " 같은 확장자 파일 자동 포함
    let ext = expand('%:e')

    if ext ==# 'c'
        let files = glob('*.c', 0, 1)
    else
        let files = glob('*.cpp', 0, 1)
    endif

    let sources = join(map(files, 'shellescape(v:val)'), ' ')

    let flags = '-g -Wall -Wextra'

    execute '!' . bin . ' ' . flags . ' ' . sources . ' -o ' . shellescape(exe)

    if v:shell_error != 0
        echo "컴파일 실패"
        return ''
    endif

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
    call term_start(['gdb', '-q', './' . exe], {
        \ 'exit_cb': function('s:GdbExitHandler'),
        \ 'curwin': 1
        \ })

    call feedkeys("break main\nrun\n", 't')
endfunction

" ================================
" 10. 단축키
" ================================
let mapleader=" "

nnoremap <F5> :w<CR>:call <SID>Run()<CR>
nnoremap <F6> :w<CR>:call <SID>Build()<CR>
nnoremap <F7> :w<CR>:call <SID>Valgrind('basic')<CR>
nnoremap <F8> :w<CR>:call <SID>Valgrind('full')<CR>
nnoremap <leader>d :w<CR>:call <SID>GDB()<CR>

" GDB 내부 키
tnoremap <F10> <C-\><C-n>:call chansend(b:terminal_job_id, "next\n")<CR>
tnoremap <F11> <C-\><C-n>:call chansend(b:terminal_job_id, "step\n")<CR>
tnoremap <F12> <C-\><C-n>:call chansend(b:terminal_job_id, "continue\n")<CR>
tnoremap <leader>b <C-\><C-n>:call chansend(b:terminal_job_id, "break " . expand('%:p') . ":" . line('.') . "\n")<CR>

" ================================
" 11. 기타 단축키
" ================================
nnoremap <C-n> :NERDTreeToggle<CR>
nnoremap <C-p> :Files<CR>
nnoremap <leader>f :Rg<CR>

inoremap jk <Esc>
inoremap kj <Esc>
inoremap <expr> <CR> pumvisible() ? coc#_select_confirm() : "\<CR>"
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

" ================================
" 12. WSL 클립보드
" ================================
let g:clipboard = {
    \ 'name': 'win32yank',
    \ 'copy': { '+': 'win32yank.exe -i --crlf', '*': 'win32yank.exe -i --crlf' },
    \ 'paste': { '+': 'win32yank.exe -o --lf', '*': 'win32yank.exe -o --lf' },
    \ 'cache_enabled': 0,
    \ }

" ================================
" 13. 커서 모양 고정
" ================================
set guicursor=
let &t_EI = "\e[1 q"
let &t_SI = "\e[5 q"
au VimEnter * silent !echo -ne "\e[1 q"
au VimLeave * silent !echo -ne "\e[1 q"
