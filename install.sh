#!/bin/bash
set -e

echo " Setting up C/C++ development environment..."

# 1. 심볼릭 링크 연결
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
