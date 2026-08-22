" =================================================================
" C/C++ Vim Configuration
"
" C++20/23
" CMake / CTest / GoogleTest
" CMake File API
" ASan / Valgrind / GDB
"
" Build:
"   build-asan/
"   build-valgrind/
" =================================================================


" =================================================================
" 1. Basic
" =================================================================

set nocompatible

set encoding=utf-8
set fileencodings=utf-8,cp949
scriptencoding utf-8

set ttimeout
set ttimeoutlen=40

" gf system include
set isfname+=~,*,?,[,],-
set path=.,/usr/include/c++/*,/usr/include,/usr/local/include,,
set suffixesadd=.h,.c,.cc,.C,.cpp,.hpp

" Search / Split
set ignorecase
set smartcase
set autoread
set splitbelow
set splitright


" =================================================================
" 2. Plugins
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
" 3. UI / Theme
" =================================================================

filetype plugin indent on
syntax on

set number
set cursorline
set signcolumn=yes
set colorcolumn=100

set termguicolors
set background=dark

let g:gruvbox_contrast_dark = 'medium'
let g:gruvbox_bold = 0
let g:gruvbox_italic = 0

colorscheme gruvbox

let g:airline_theme = 'gruvbox'
let g:airline_powerline_fonts = 0

let g:vim_json_conceal = 0
set conceallevel=0

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


" =================================================================
" 4. Editing
" =================================================================

let g:indentLine_char = '┊'
let g:indentLine_color_gui = '#504945'

set autoindent
set cindent
set tabstop=2
set shiftwidth=2
set expandtab

set completeopt=noinsert,menuone
set clipboard=unnamedplus


" =================================================================
" 5. Build Profiles / State
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

let s:selected_targets = {
      \ 'executable': '',
      \ 'test': ''
      \ }

let s:gdb_bufnr = -1


function! s:GetProfile(name) abort
  return get(s:profiles, a:name, {})
endfunction


" =================================================================
" 6. CMake File API
" =================================================================

function! s:PrepareCMakeFileAPI(build_dir) abort
  let l:dir = a:build_dir . '/.cmake/api/v1/query/client-vim'
  call mkdir(l:dir, 'p')
  call writefile([], l:dir . '/codemodel-v2')
endfunction


function! s:GetCodeModelReply(build_dir) abort
  let l:dir = a:build_dir . '/.cmake/api/v1/reply'

  if !isdirectory(l:dir)
    return ''
  endif

  let l:files = glob(l:dir . '/codemodel-v2-*.json', 0, 1)

  if empty(l:files)
    return ''
  endif

  call sort(l:files, { a, b -> getftime(a) - getftime(b) })
  return l:files[-1]
endfunction


function! s:GetExecutableTargets(build_dir) abort
  let l:reply = s:GetCodeModelReply(a:build_dir)

  if empty(l:reply)
    return []
  endif

  try
    let l:model = json_decode(join(readfile(l:reply), "\n"))
  catch
    echoerr 'CMake CodeModel JSON 파싱 실패'
    return []
  endtry

  let l:targets = []

  for l:config in get(l:model, 'configurations', [])
    for l:ref in get(l:config, 'targets', [])
      if !has_key(l:ref, 'jsonFile')
        continue
      endif

      let l:file = fnamemodify(l:reply, ':h') . '/' . l:ref.jsonFile

      if !filereadable(l:file)
        continue
      endif

      try
        let l:target = json_decode(join(readfile(l:file), "\n"))
      catch
        continue
      endtry

      if get(l:target, 'type', '') !=# 'EXECUTABLE'
        continue
      endif

      let l:artifacts = get(l:target, 'artifacts', [])

      if empty(l:artifacts)
        continue
      endif

      let l:path = l:artifacts[0].path

      if l:path !~# '^/'
        let l:path = a:build_dir . '/' . l:path
      endif

      let l:path = resolve(fnamemodify(l:path, ':p'))

      if executable(l:path)
        call add(l:targets, {
              \ 'name': l:target.name,
              \ 'path': l:path
              \ })
      endif
    endfor
  endfor

  return l:targets
endfunction


" =================================================================
" 7. CTest
" =================================================================

function! s:GetCTestJSON(build_dir) abort
  if !isdirectory(a:build_dir)
    return {}
  endif

  let l:cmd =
        \ 'ctest --test-dir '
        \ . shellescape(a:build_dir)
        \ . ' --show-only=json-v1'

  let l:output = system(l:cmd)

  if v:shell_error != 0
    return {}
  endif

  try
    return json_decode(l:output)
  catch
    echoerr 'CTest JSON 파싱 실패'
    return {}
  endtry
endfunction


function! s:NormalizePath(path, base) abort
  if empty(a:path)
    return ''
  endif

  if a:path =~# '^/'
    return resolve(fnamemodify(a:path, ':p'))
  endif

  return resolve(fnamemodify(a:base . '/' . a:path, ':p'))
endfunction


function! s:GetTestTargets(build_dir) abort
  let l:ctest = s:GetCTestJSON(a:build_dir)

  if empty(l:ctest) || !has_key(l:ctest, 'tests')
    return []
  endif

  let l:map = {}

  for l:target in s:GetExecutableTargets(a:build_dir)
    let l:path = resolve(fnamemodify(l:target.path, ':p'))

    let l:map[l:path] = {
          \ 'name': l:target.name,
          \ 'path': l:path,
          \ 'tests': []
          \ }
  endfor

  let l:default_base = resolve(fnamemodify(a:build_dir, ':p'))

  for l:test in l:ctest.tests
    let l:command = get(l:test, 'command', [])

    if empty(l:command)
      continue
    endif

    let l:base = get(
          \ l:test,
          \ 'workingDirectory',
          \ l:default_base
          \ )

    let l:path = s:NormalizePath(l:command[0], l:base)

    if has_key(l:map, l:path)
      call add(
            \ l:map[l:path].tests,
            \ get(l:test, 'name', '(unnamed)')
            \ )
    endif
  endfor

  return filter(values(l:map), { _, target -> !empty(target.tests) })
endfunction


" =================================================================
" 8. compile_commands.json
" =================================================================

function! s:UpdateCompileCommands(build_dir) abort
  let l:source = a:build_dir . '/compile_commands.json'

  if !filereadable(l:source)
    return
  endif

  call system(
        \ 'ln -sfn '
        \ . shellescape(l:source)
        \ . ' '
        \ . shellescape('compile_commands.json')
        \ )

  if v:shell_error != 0
    echoerr 'compile_commands.json 심볼릭 링크 생성 실패'
  endif
endfunction


" =================================================================
" 9. Builder
" =================================================================

function! s:Build(profile_name) abort
  let l:profile = s:GetProfile(a:profile_name)

  if empty(l:profile)
    echoerr '알 수 없는 Build Profile: ' . a:profile_name
    return 0
  endif

  let l:build_dir = l:profile.build_dir

  call mkdir(l:build_dir, 'p')
  call s:PrepareCMakeFileAPI(l:build_dir)

  echo 'CMake Configure & Build 중...'
  echo 'Profile: ' . a:profile_name
  echo 'Build directory: ' . l:build_dir

  let l:args = join(
        \ map(copy(l:profile.cmake_args), 'shellescape(v:val)'),
        \ ' '
        \ )

  let l:cmd =
        \ 'cmake -S . -B '
        \ . shellescape(l:build_dir)
        \ . ' '
        \ . l:args
        \ . ' && cmake --build '
        \ . shellescape(l:build_dir)

  execute '!' . l:cmd

  if v:shell_error != 0
    redraw!
    echoerr 'CMake 빌드 실패'
    return 0
  endif

  if get(l:profile, 'compile_commands', 0)
    call s:UpdateCompileCommands(l:build_dir)
  endif

  redraw!
  echo 'CMake 빌드 성공'

  return 1
endfunction


" =================================================================
" 10. Target Provider / Selector
" =================================================================

function! s:GetTargets(profile_name, kind) abort
  let l:profile = s:GetProfile(a:profile_name)

  if empty(l:profile)
    return []
  endif

  if a:kind ==# 'executable'
    return s:GetExecutableTargets(l:profile.build_dir)
  endif

  if a:kind ==# 'test'
    return s:GetTestTargets(l:profile.build_dir)
  endif

  echoerr '알 수 없는 Target Kind: ' . a:kind
  return []
endfunction


function! s:SelectTarget(profile_name, kind, ...) abort
  let l:force = get(a:, 1, 0)
  let l:targets = s:GetTargets(a:profile_name, a:kind)

  if empty(l:targets)
    echoerr 'Target을 찾을 수 없습니다.'
    return {}
  endif

  let l:selected_name = get(s:selected_targets, a:kind, '')

  if !l:force && !empty(l:selected_name)
    for l:target in l:targets
      if l:target.name ==# l:selected_name
        return l:target
      endif
    endfor
  endif

  if len(l:targets) == 1
    let l:selected = l:targets[0]
  else
    let l:menu = ['Target 선택:']
    let l:index = 1

    for l:target in l:targets
      if a:kind ==# 'test'
        let l:label = printf(
              \ '%d. %s [%d tests]',
              \ l:index,
              \ l:target.name,
              \ len(l:target.tests)
              \ )
      else
        let l:label = printf('%d. %s', l:index, l:target.name)
      endif

      call add(l:menu, l:label)
      let l:index += 1
    endfor

    let l:choice = inputlist(l:menu)

    if l:choice <= 0 || l:choice > len(l:targets)
      echo 'Target 선택 취소'
      return {}
    endif

    let l:selected = l:targets[l:choice - 1]
  endif

  let s:selected_targets[a:kind] = l:selected.name
  return l:selected
endfunction


function! s:ChooseTarget(kind) abort
  let l:target = s:SelectTarget('asan', a:kind, 1)

  if !empty(l:target)
    echo '선택된 target: ' . l:target.name
  endif
endfunction


" =================================================================
" 11. Runners
" =================================================================

function! s:RunDirect(target) abort
  execute '!' . shellescape(a:target.path)
endfunction


function! s:RunValgrind(target) abort
  execute
        \ '!valgrind '
        \ . '--leak-check=full '
        \ . '--show-leak-kinds=all '
        \ . '--track-origins=yes '
        \ . shellescape(a:target.path)
endfunction


function! s:GdbExitHandler(job_id, data) abort
  let s:gdb_bufnr = -1
  echo 'GDB 종료'
endfunction


function! s:RunGDB(target) abort
  botright 12split

  let s:gdb_bufnr = term_start(
        \ ['gdb', '-q', a:target.path],
        \ {
        \   'exit_cb': function('s:GdbExitHandler'),
        \   'curwin': 1,
        \   'term_name': 'gdb-inferior'
        \ })

  call term_sendkeys(
        \ s:gdb_bufnr,
        \ "break main\nrun\n"
        \ )
endfunction


let s:runners = {
      \ 'direct': function('s:RunDirect'),
      \ 'valgrind': function('s:RunValgrind'),
      \ 'gdb': function('s:RunGDB')
      \ }


function! s:Run(target, runner) abort
  let l:runner = get(s:runners, a:runner, v:null)

  if l:runner is v:null
    echoerr '알 수 없는 Runner: ' . a:runner
    return
  endif

  call l:runner(a:target)
endfunction


" =================================================================
" 12. Build + Select + Run Pipeline
" =================================================================

function! s:BuildAndRun(profile, kind, runner) abort
  if !s:Build(a:profile)
    return
  endif

  let l:target = s:SelectTarget(a:profile, a:kind)

  if empty(l:target)
    return
  endif

  call s:Run(l:target, a:runner)
endfunction


" =================================================================
" 13. CTest
" =================================================================

function! s:RunCTest(pattern) abort
  if !s:Build('asan')
    return
  endif

  let l:profile = s:GetProfile('asan')

  let l:cmd =
        \ 'ctest --test-dir '
        \ . shellescape(l:profile.build_dir)

  if !empty(a:pattern)
    let l:cmd .= ' -R ' . shellescape(a:pattern)
  endif

  let l:cmd .= ' --output-on-failure'

  execute '!' . l:cmd
endfunction


function! s:RunCTestCurrentModule() abort
  let l:module = expand('%:p:h:t')

  if l:module ==# 'tests'
    let l:module = expand('%:p:h:h:t')
  endif

  echo '모듈 테스트 실행: ' . l:module
  call s:RunCTest(l:module)
endfunction


" =================================================================
" 14. GDB Command
" =================================================================

function! s:SendGdbCommand(cmd) abort
  if s:gdb_bufnr == -1 || !bufexists(s:gdb_bufnr)
    echo '실행 중인 GDB 터미널을 찾을 수 없습니다.'
    return
  endif

  call term_sendkeys(s:gdb_bufnr, a:cmd . "\n")
endfunction


" =================================================================
" 15. Leader
" =================================================================

let mapleader = ' '


" =================================================================
" 16. LSP / File Switch
" =================================================================

nnoremap <F1>
      \ :CocCommand document.toggleInlayHint<CR>

nnoremap <F4>
      \ :FSHere<CR>


" =================================================================
" 17. Build / Run
" =================================================================

" F5 : ASan Build
nnoremap <F5>
      \ :w<CR>
      \ :call <SID>Build('asan')<CR>

" F6 : ASan Build + Run
nnoremap <F6>
      \ :w<CR>
      \ :call <SID>BuildAndRun('asan', 'executable', 'direct')<CR>

" F8 : Valgrind Build
nnoremap <F8>
      \ :w<CR>
      \ :call <SID>Build('valgrind')<CR>

" F9 : Valgrind Build + Run
nnoremap <F9>
      \ :w<CR>
      \ :call <SID>BuildAndRun(
      \ 'valgrind',
      \ 'executable',
      \ 'valgrind'
      \ )<CR>

" <leader>r : executable target 재선택
nnoremap <leader>r
      \ :call <SID>ChooseTarget('executable')<CR>


" =================================================================
" 18. CTest / GTest
" =================================================================

" 전체 CTest
nnoremap <leader>t
      \ :w<CR>
      \ :call <SID>RunCTest('')<CR>

" 현재 모듈 CTest
nnoremap <leader>f
      \ :w<CR>
      \ :call <SID>RunCTestCurrentModule()<CR>

" GTest executable 직접 실행
nnoremap <leader>g
      \ :w<CR>
      \ :call <SID>BuildAndRun('asan', 'test', 'direct')<CR>


" =================================================================
" 19. GDB
" =================================================================

" GDB 실행
nnoremap <leader>d
      \ :w<CR>
      \ :call <SID>BuildAndRun('asan', 'executable', 'gdb')<CR>

" 현재 줄 breakpoint
nnoremap <leader>b
      \ :call <SID>SendGdbCommand(
      \ 'break '
      \ . expand('%:t')
      \ . ':'
      \ . line('.')
      \ )<CR>


" =================================================================
" 20. GDB Step
" =================================================================

nnoremap <F10>
      \ :call <SID>SendGdbCommand('next')<CR>

tnoremap <F10>
      \ <C-\><C-n>
      \ :call <SID>SendGdbCommand('next')<CR>i

nnoremap <F11>
      \ :call <SID>SendGdbCommand('step')<CR>

tnoremap <F11>
      \ <C-\><C-n>
      \ :call <SID>SendGdbCommand('step')<CR>i

nnoremap <F12>
      \ :call <SID>SendGdbCommand('continue')<CR>

tnoremap <F12>
      \ <C-\><C-n>
      \ :call <SID>SendGdbCommand('continue')<CR>i


" =================================================================
" 21. CoC / LSP
" =================================================================

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


" =================================================================
" 22. Code Format
" =================================================================

function! FormatCode() abort
  if CocHasProvider('format')
    call CocAction('format')
  else
    normal! gg=G
    echo 'LSP Formatter 미연동: gg=G 적용'
  endif
endfunction

nnoremap <silent> <leader>cf
      \ :call FormatCode()<CR>


" =================================================================
" 23. File Search
" =================================================================

nnoremap <C-n>
      \ :NERDTreeToggle<CR>

nnoremap <C-p>
      \ :Files<CR>

nnoremap <leader>rg
      \ :Rg<CR>


" =================================================================
" 24. Insert Mode
" =================================================================

inoremap jk <Esc>
inoremap kj <Esc>


" =================================================================
" 25. coc.nvim Completion
" =================================================================

function! s:check_back_space() abort
  let l:col = col('.') - 1

  return !l:col
        \ || getline('.')[l:col - 1] =~# '\s'
endfunction


inoremap <silent><expr> <CR>
      \ coc#pum#visible()
      \ ? coc#pum#confirm()
      \ : "\<C-g>u\<CR>\<C-r>=coc#on_enter()\<CR>"

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


" =================================================================
" 26. vim-fswitch
" =================================================================

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


" =================================================================
" 27. WSL Clipboard
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
" 28. Cursor Shape
" =================================================================

if !has('gui_running')
  let &t_SI = "\<Esc>[5 q"
  let &t_EI = "\<Esc>[2 q"
  let &t_SR = "\<Esc>[3 q"
endif


" =================================================================
" 29. Misc
" =================================================================

nnoremap <silent> <Esc><Esc>
      \ :nohlsearch<CR>

