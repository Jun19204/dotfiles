" =================================================================
" C/C++ Vim Configuration
" C++20/23 | CMake | CTest | GoogleTest | ASan | Valgrind | GDB
" =================================================================

set nocompatible
set encoding=utf-8
set fileencodings=utf-8,cp949
scriptencoding utf-8
set ttimeout ttimeoutlen=40
set isfname+=~,*,?,[,],-
set path=.,/usr/include/c++/*,/usr/include,/usr/local/include,,
set suffixesadd=.h,.c,.cc,.C,.cpp,.hpp
set ignorecase smartcase autoread
set splitbelow splitright

" =================================================================
" Plugins
" =================================================================
call plug#begin('~/.vim/plugged')
Plug 'preservim/nerdtree'
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'vim-airline/vim-airline'
Plug 'junegunn/fzf', {'do': { -> fzf#install() }}
Plug 'junegunn/fzf.vim'
Plug 'Yggdroot/indentLine'
Plug 'morhetz/gruvbox'
Plug 'derekwyatt/vim-fswitch'
Plug 'pboettch/vim-cmake-syntax'
call plug#end()

" =================================================================
" UI / Editing
" =================================================================
filetype plugin indent on
syntax on

set number cursorline
set termguicolors background=dark
set autoindent cindent
set tabstop=2 shiftwidth=2 expandtab
set completeopt=noinsert,menuone
set clipboard=unnamedplus
set signcolumn=yes
set colorcolumn=100
set conceallevel=0

let g:gruvbox_contrast_dark = 'medium'
let g:gruvbox_bold = 0
let g:gruvbox_italic = 0
colorscheme gruvbox

let g:airline_theme = 'gruvbox'
let g:airline_powerline_fonts = 0
let g:vim_json_conceal = 0

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

" =================================================================
" State
" =================================================================
let s:selected_targets = {}
let s:gdb_bufnr = -1

" =================================================================
" Build Profiles
" =================================================================
let s:profiles = {
      \ 'asan': {
      \   'build_dir': 'build-asan',
      \   'cmake_args': [
      \     '-DCMAKE_BUILD_TYPE=Debug',
      \     '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
      \     '-DUSE_SANITIZER=ON'
      \   ],
      \   'compile_commands': 1
      \ },
      \ 'valgrind': {
      \   'build_dir': 'build-valgrind',
      \   'cmake_args': [
      \     '-DCMAKE_BUILD_TYPE=Debug',
      \     '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
      \     '-DUSE_SANITIZER=OFF'
      \   ],
      \   'compile_commands': 0
      \ }
      \ }

function! s:GetProfile(name) abort
  return get(s:profiles, a:name, {})
endfunction

" =================================================================
" Project Root
" =================================================================
function! s:FindUp(start, name) abort
  let l:path = findfile(a:name, a:start . ';')
  return empty(l:path) ? '' : fnamemodify(l:path, ':p:h')
endfunction

function! s:FindUpDir(start, name) abort
  let l:path = finddir(a:name, a:start . ';')
  return empty(l:path) ? '' : fnamemodify(l:path, ':p:h')
endfunction

function! s:GetProjectRoot() abort
  let l:file = expand('%:p')
  let l:start = empty(l:file) ? getcwd() : fnamemodify(l:file, ':h')

  " 가장 가까운 CMake 프로젝트를 우선
  let l:root = s:FindUp(l:start, 'CMakeLists.txt')
  if !empty(l:root)
    return resolve(l:root)
  endif

  " CMakePresets 기반 프로젝트
  let l:root = s:FindUp(l:start, 'CMakePresets.json')
  if !empty(l:root)
    return resolve(l:root)
  endif

  " CMakePresets가 없어도 .git 루트를 fallback으로 사용
  let l:root = s:FindUpDir(l:start, '.git')
  if !empty(l:root)
    return resolve(l:root)
  endif

  return resolve(fnamemodify(getcwd(), ':p'))
endfunction

function! s:GetBuildDir(profile) abort
  let l:p = s:GetProfile(a:profile)
  return empty(l:p) ? '' : s:GetProjectRoot() . '/' . l:p.build_dir
endfunction

" =================================================================
" CMake File API
" =================================================================
function! s:PrepareFileAPI(build_dir) abort
  let l:dir = a:build_dir . '/.cmake/api/v1/query/client-vim'
  call mkdir(l:dir, 'p')
  call writefile([], l:dir . '/codemodel-v2')
endfunction

function! s:GetCodeModel(build_dir) abort
  let l:files = glob(a:build_dir . '/.cmake/api/v1/reply/codemodel-v2-*.json', 0, 1)
  if empty(l:files)
    return ''
  endif
  call sort(l:files, { a, b -> getftime(a) - getftime(b) })
  return l:files[-1]
endfunction

function! s:ReadJSON(file) abort
  if !filereadable(a:file)
    return {}
  endif
  try
    return json_decode(join(readfile(a:file), "\n"))
  catch
    return {}
  endtry
endfunction

function! s:GetExecutableTargets(build_dir) abort
  let l:model = s:GetCodeModel(a:build_dir)
  let l:data = s:ReadJSON(l:model)
  let l:targets = []

  for l:config in get(l:data, 'configurations', [])
    for l:ref in get(l:config, 'targets', [])
      let l:file = fnamemodify(l:model, ':h') . '/' . get(l:ref, 'jsonFile', '')
      let l:target = s:ReadJSON(l:file)
      if get(l:target, 'type', '') !=# 'EXECUTABLE'
        continue
      endif

      let l:artifacts = get(l:target, 'artifacts', [])
      if empty(l:artifacts)
        continue
      endif

      let l:path = get(l:artifacts[0], 'path', '')
      if l:path !~# '^/'
        let l:path = a:build_dir . '/' . l:path
      endif

      let l:path = resolve(fnamemodify(l:path, ':p'))
      if executable(l:path)
        call add(l:targets, {'name': get(l:target, 'name', ''), 'path': l:path})
      endif
    endfor
  endfor

  return l:targets
endfunction

" =================================================================
" CTest
" =================================================================
function! s:GetCTestJSON(build_dir) abort
  if !isdirectory(a:build_dir)
    return {}
  endif

  let l:cmd = 'ctest --test-dir ' . shellescape(a:build_dir) . ' --show-only=json-v1'
  let l:output = system(l:cmd)
  return v:shell_error == 0 ? s:DecodeCTestJSON(l:output) : {}
endfunction

function! s:DecodeCTestJSON(output) abort
  try
    return json_decode(a:output)
  catch
    echoerr 'CTest JSON 파싱 실패'
    return {}
  endtry
endfunction

function! s:NormalizePath(path, base) abort
  if empty(a:path)
    return ''
  endif
  let l:path = a:path =~# '^/' ? a:path : a:base . '/' . a:path
  return resolve(fnamemodify(l:path, ':p'))
endfunction

function! s:GetTestTargets(build_dir) abort
  let l:ctest = s:GetCTestJSON(a:build_dir)
  let l:executables = s:GetExecutableTargets(a:build_dir)
  if empty(get(l:ctest, 'tests', [])) || empty(l:executables)
    return []
  endif

  let l:map = {}
  for l:target in l:executables
    let l:map[l:target.path] = {
          \ 'name': l:target.name,
          \ 'path': l:target.path,
          \ 'tests': []
          \ }
  endfor

  let l:default = resolve(fnamemodify(a:build_dir, ':p'))
  for l:test in l:ctest.tests
    let l:command = get(l:test, 'command', [])
    if empty(l:command)
      continue
    endif

    let l:base = get(l:test, 'workingDirectory', l:default)
    let l:path = s:NormalizePath(l:command[0], l:base)

    if has_key(l:map, l:path)
      call add(l:map[l:path].tests, get(l:test, 'name', '(unnamed)'))
    endif
  endfor

  return filter(values(l:map), { _, target -> !empty(target.tests) })
endfunction

" =================================================================
" Build
" =================================================================
function! s:UpdateCompileCommands(build_dir) abort
  let l:source = a:build_dir . '/compile_commands.json'
  if !filereadable(l:source)
    return
  endif

  let l:dest = s:GetProjectRoot() . '/compile_commands.json'
  call system('ln -sfn ' . shellescape(l:source) . ' ' . shellescape(l:dest))

  if v:shell_error != 0
    echoerr 'compile_commands.json 심볼릭 링크 생성 실패'
  endif
endfunction

function! s:Build(profile) abort
  let l:p = s:GetProfile(a:profile)
  if empty(l:p)
    echoerr '알 수 없는 Build Profile: ' . a:profile
    return 0
  endif

  let l:root = s:GetProjectRoot()
  let l:build = l:root . '/' . l:p.build_dir

  call mkdir(l:build, 'p')
  call s:PrepareFileAPI(l:build)

  echo 'Project: ' . l:root
  echo 'Profile: ' . a:profile
  echo 'Build: ' . l:build

  let l:cmd = 'cmake -S ' . shellescape(l:root)
        \ . ' -B ' . shellescape(l:build)
        \ . ' ' . join(l:p.cmake_args, ' ')
        \ . ' && cmake --build ' . shellescape(l:build)

  execute '!' . l:cmd

  if v:shell_error != 0
    redraw!
    echoerr 'CMake 빌드 실패'
    return 0
  endif

  if get(l:p, 'compile_commands', 0)
    call s:UpdateCompileCommands(l:build)
  endif

  redraw!
  echo 'CMake 빌드 성공'
  return 1
endfunction

" =================================================================
" Target Selection
" =================================================================
function! s:GetTargets(profile, kind) abort
  let l:build = s:GetBuildDir(a:profile)
  if a:kind ==# 'test'
    return s:GetTestTargets(l:build)
  endif
  return s:GetExecutableTargets(l:build)
endfunction

function! s:SelectTarget(profile, kind, force) abort
  let l:targets = s:GetTargets(a:profile, a:kind)
  if empty(l:targets)
    echoerr '실행 가능한 target을 찾을 수 없습니다.'
    return {}
  endif

  let l:key = a:profile . ':' . a:kind
  if !a:force && has_key(s:selected_targets, l:key)
    for l:target in l:targets
      if l:target.name ==# s:selected_targets[l:key]
        return l:target
      endif
    endfor
  endif

  if len(l:targets) == 1
    let s:selected_targets[l:key] = l:targets[0].name
    return l:targets[0]
  endif

  let l:menu = ['Target 선택:']
  let l:index = 1

  for l:target in l:targets
    let l:label = a:kind ==# 'test'
          \ ? printf('%d. %s [%d tests]', l:index, l:target.name, len(l:target.tests))
          \ : printf('%d. %s', l:index, l:target.name)
    call add(l:menu, l:label)
    let l:index += 1
  endfor

  let l:choice = inputlist(l:menu)
  if l:choice <= 0 || l:choice > len(l:targets)
    echo 'Target 선택 취소'
    return {}
  endif

  let l:target = l:targets[l:choice - 1]
  let s:selected_targets[l:key] = l:target.name
  return l:target
endfunction

function! s:ChooseTarget(profile, kind) abort
  call remove(s:selected_targets, a:profile . ':' . a:kind)
  let l:target = s:SelectTarget(a:profile, a:kind, 1)
  if !empty(l:target)
    echo '선택된 target: ' . l:target.name
  endif
endfunction

" =================================================================
" Runners
" =================================================================
function! s:RunExecutable(profile, command) abort
  if !s:Build(a:profile)
    return
  endif

  let l:target = s:SelectTarget(a:profile, 'executable', 0)
  if empty(l:target)
    return
  endif

  let l:cmd = empty(a:command) ? shellescape(l:target.path)
        \ : a:command . ' ' . shellescape(l:target.path)

  echo 'Run: ' . l:target.name
  execute '!' . l:cmd
endfunction

function! s:RunASan() abort
  call s:RunExecutable('asan', '')
endfunction

function! s:RunValgrind() abort
  call s:RunExecutable(
        \ 'valgrind',
        \ 'valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes'
        \ )
endfunction

function! s:RunCTest(pattern) abort
  if !s:Build('asan')
    return
  endif

  let l:cmd = 'ctest --test-dir ' . shellescape(s:GetBuildDir('asan'))
  if !empty(a:pattern)
    let l:cmd .= ' -R ' . shellescape(a:pattern)
  endif

  execute '!' . l:cmd . ' --output-on-failure'
endfunction

function! s:RunCTestCurrentModule() abort
  let l:dir = expand('%:p:h')
  let l:module = fnamemodify(l:dir, ':t')

  if l:module ==# 'tests'
    let l:module = fnamemodify(l:dir, ':h:t')
  endif

  call s:RunCTest(l:module)
endfunction

function! s:RunGTest() abort
  if !s:Build('asan')
    return
  endif

  let l:target = s:SelectTarget('asan', 'test', 0)
  if !empty(l:target)
    execute '!' . shellescape(l:target.path)
  endif
endfunction

" =================================================================
" GDB
" =================================================================
function! s:GdbExitHandler(job, status) abort
  let s:gdb_bufnr = -1
  echo 'GDB 종료'
endfunction

function! s:RunGDB() abort
  if !s:Build('asan')
    return
  endif

  let l:target = s:SelectTarget('asan', 'executable', 0)
  if empty(l:target)
    return
  endif

  botright 12split
  let s:gdb_bufnr = term_start(
        \ ['gdb', '-q', l:target.path],
        \ {
        \   'exit_cb': function('s:GdbExitHandler'),
        \   'curwin': 1,
        \   'term_name': 'gdb-inferior'
        \ }
        \ )

  call term_sendkeys(s:gdb_bufnr, "break main\nrun\n")
endfunction

function! s:SendGdbCommand(cmd) abort
  if s:gdb_bufnr != -1 && bufexists(s:gdb_bufnr)
    call term_sendkeys(s:gdb_bufnr, a:cmd . "\n")
  else
    echo '실행 중인 GDB 터미널을 찾을 수 없습니다.'
  endif
endfunction

function! s:SetBreakpoint() abort
  let l:file = expand('%:t')
  call s:SendGdbCommand('break ' . l:file . ':' . line('.'))
endfunction

" =================================================================
" Formatting
" =================================================================
function! s:FormatCode() abort
  if CocHasProvider('format')
    call CocAction('format')
  else
    normal! gg=G
    echo 'LSP Formatter 미연동: gg=G 적용'
  endif
endfunction

" =================================================================
" Leader / Build / Test
" =================================================================
let mapleader = ' '

nnoremap <F5> :w<CR>:call <SID>Build('asan')<CR>
nnoremap <F6> :w<CR>:call <SID>RunASan()<CR>
nnoremap <F8> :w<CR>:call <SID>Build('valgrind')<CR>
nnoremap <F9> :w<CR>:call <SID>RunValgrind()<CR>

nnoremap <leader>r :call <SID>ChooseTarget('asan', 'executable')<CR>
nnoremap <leader>t :w<CR>:call <SID>RunCTest('')<CR>
nnoremap <leader>f :w<CR>:call <SID>RunCTestCurrentModule()<CR>
nnoremap <leader>g :w<CR>:call <SID>RunGTest()<CR>

" =================================================================
" GDB
" =================================================================
nnoremap <leader>d :w<CR>:call <SID>RunGDB()<CR>
nnoremap <leader>b :call <SID>SetBreakpoint()<CR>

nnoremap <F10> :call <SID>SendGdbCommand('next')<CR>
tnoremap <F10> <C-\><C-n>:call <SID>SendGdbCommand('next')<CR>i

nnoremap <F11> :call <SID>SendGdbCommand('step')<CR>
tnoremap <F11> <C-\><C-n>:call <SID>SendGdbCommand('step')<CR>i

nnoremap <F12> :call <SID>SendGdbCommand('continue')<CR>
tnoremap <F12> <C-\><C-n>:call <SID>SendGdbCommand('continue')<CR>i

" =================================================================
" CoC / LSP
" =================================================================
nnoremap <F1> :CocCommand document.toggleInlayHint<CR>
nnoremap <F4> :FSHere<CR>

nnoremap <silent> K :call CocActionAsync('doHover')<CR>
nnoremap <silent> gd <Plug>(coc-definition)
nnoremap <silent> gy <Plug>(coc-type-definition)
nnoremap <silent> gi <Plug>(coc-implementation)
nnoremap <silent> gr <Plug>(coc-references)
nnoremap <silent> <leader>rn <Plug>(coc-rename)
nnoremap <silent> <leader>cf :call <SID>FormatCode()<CR>

" =================================================================
" Search / Files
" =================================================================
nnoremap <C-n> :NERDTreeToggle<CR>
nnoremap <C-p> :Files<CR>
nnoremap <leader>rg :Rg<CR>

" =================================================================
" Insert / Completion
" =================================================================
inoremap jk <Esc>
inoremap kj <Esc>

function! s:CheckBackSpace() abort
  let l:col = col('.') - 1
  return !l:col || getline('.')[l:col - 1] =~# '\s'
endfunction

inoremap <silent><expr> <CR> coc#pum#visible()
      \ ? coc#pum#confirm()
      \ : "\<C-g>u\<CR>\<C-r>=coc#on_enter()\<CR>"

inoremap <silent><expr> <TAB> coc#pum#visible()
      \ ? coc#pum#next(1)
      \ : <SID>CheckBackSpace()
      \ ? "\<Tab>"
      \ : coc#refresh()

inoremap <expr> <S-TAB> coc#pum#visible()
      \ ? coc#pum#prev(1)
      \ : "\<C-h>"

" =================================================================
" vim-fswitch
" =================================================================
augroup FSwitchPaths
  autocmd!
  autocmd BufEnter *.cpp,*.cc,*.c
        \ let b:fswitchdst = 'h,hpp' |
        \ let b:fswitchlocs = 'reg:|src|include|,reg:|src|../include|,../include,.,tests'
  autocmd BufEnter *.h,*.hpp
        \ let b:fswitchdst = 'cpp,cc,c' |
        \ let b:fswitchlocs = 'reg:|include|src|,reg:|include|../src|,../src,.,tests'
augroup END

" =================================================================
" WSL Clipboard
" =================================================================
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

" =================================================================
" Cursor Shape
" =================================================================
if !has('gui_running')
  let &t_SI = "\<Esc>[5 q"
  let &t_EI = "\<Esc>[2 q"
  let &t_SR = "\<Esc>[3 q"
endif

" =================================================================
" Misc
" =================================================================
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

