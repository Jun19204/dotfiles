#!/bin/bash
set -e

echo " Setting up C/C++ development environment..."

# 0. 필수 패키지 (clangd, nodejs, curl) 사전 체크 및 자동 설치
echo " Checking required system packages (clangd, nodejs, curl)..."

MISSING_PACKAGES=()

if ! command -v clangd &> /dev/null; then
    MISSING_PACKAGES+=("clangd")
fi

if ! command -v node &> /dev/null; then
    MISSING_PACKAGES+=("nodejs")
fi

if ! command -v curl &> /dev/null; then
    MISSING_PACKAGES+=("curl")
fi

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo " Installing missing packages: ${MISSING_PACKAGES[*]}..."
    sudo apt update
    sudo apt install -y "${MISSING_PACKAGES[@]}"
else
    echo " All required packages are already installed."
fi

# 1. 심볼릭 링크 연결
echo " Linking dotfiles..."
ln -sf ~/dotfiles/.vimrc ~/.vimrc
mkdir -p ~/.vim
ln -sf ~/dotfiles/.vim/coc-settings.json ~/.vim/coc-settings.json

# 2. vim-plug 자동 설치 (없는 경우)
if [ ! -f ~/.vim/autoload/plug.vim ]; then
  echo " Installing vim-plug..."
  curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

# 3. Vim 플러그인 및 coc-clangd 자동 설치
echo " Installing Vim plugins & coc-clangd..."
vim +PlugInstall +qall
vim +":CocInstall -sync coc-clangd" +qall

echo " Environment setup complete!"
