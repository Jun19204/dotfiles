# Modern C/C++ Dev Environment (.dotfiles)
Modern C++20 및 C 개발 환경 구축을 위한 Vim 및 `coc-clangd` 중심의 통합 설정입니다.  
CMake, GDB, Valgrind, Inlay Hints 토글, 헤더/소스 고속 스위칭 및 WSL 환경 최적화 설정을 포함합니다.

------------------------------------------

## One-Line Installation
새로운 환경이나 다른 서버에서 아래 **단 한 줄의 명령어**를 터미널에 입력하면 모든 설정, 플러그인, `coc-clangd`까지 자동으로 세팅됩니다.
```bash
git clone [https://github.com/Jun19204/dotfiles.git](https://github.com/Jun19204/dotfiles.git) ~/dotfiles && ~/dotfiles/install.sh
```
------------------------------------------

## 필수 의존성 (Ubuntu/WSL 사전 설치 권장)
```bash
sudo apt update && sudo apt install -y build-essential cmake gdb valgrind clangd ripgrep win32yank
```
------------------------------------------

## Keybindings Summary
 <leader> 키는 Space(스페이스바)로 설정되어 있습니다.
### Code & LSP Navigation
| Key | Description |
| :--- | :--- |
| `gd` | 정의로 이동 (Go to Definition) |
| `gy` | 타입 정의로 이동 (Go to Type Definition) |
| `gi` | 구현부로 이동 (Go to Implementation) |
| `gr` | 참조 목록 확인 (Go to References) |
| `K` | 심볼/함수 문서 팝업 열기 (Hover Document) |
| `<leader>rn` | 심볼/변수 이름 일괄 변경 (Rename) |
| `<leader>cf` | clang-format 기반 전체 코드 자동 정렬 |
| `<F1>` | auto 및 매개변수 타입 Inlay Hints 토글 (ON/OFF) |
| `<F4>` | 헤더/소스 파일 스위칭 (.h $\leftrightarrow$ .cpp) |

### CMake / Build / Debug / Profile
| Key | Description |
| :--- | :--- |
| `<F5>` | CMake 자동 빌드 후 바이너리 실행 |
| `<F6>` | CMake 프로젝트 빌드 (cmake --build build) |
| `<F7>` | Valgrind 누수 검사 (기본) |
| `<F8>` | Valgrind 메모리 전체 검사 (--leak-check=full) |
| `<leader>d` | GDB 디버거 실행 (하단 분할 터미널 창) |
| `<leader>b` | 현재 커서 위치에 GDB Breakpoint 설정 |
| `<F10> / <F11> / <F12>` | GDB 내에서 Next / Step / Continue 실행 |

### File Management & Utility
| (Key) | (Description) |
| --- | --- |
| `Ctrl + n` | NERDTree 파일 탐색기 토글 |
| `Ctrl + p` | FZF 파일 이름 고속 검색 |
| `<leader>f` | Ripgrep (Rg) 기반 프로젝트 내 코드 내용 검색 |
| `Esc + Esc` | 검색 하이라이트 해제 |
| `jk or kj` | Insert 모드에서 Normal 모드로 탈출 |

------------------------------------------

## Features & Architecture
- Standard: C++20 최신 문법, 콘셉트(Concepts), 템플릿 메타프로그래밍 하이라이트 지원
- Formatter Alignment: Vim 들여쓰기 2칸(shiftwidth=2)과 clangd 포맷터 간격 완벽 동기화
- Auto Sync: CMake 빌드 시 compile_commands.json 심볼릭 링크 자동 생성으로 LSP 인덱싱 자동 보장
- WSL Optimization: win32yank 연동으로 Windows-WSL 간 클립보드 공유 및 터미널 커서 모양 가비지 방지 EOF


