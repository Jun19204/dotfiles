cat << 'EOF' > install.sh
#!/bin/bash

echo "Setting up dotfiles..."

# 1. 심볼릭 링크 연결
ln -sf ~/dotfiles/.vimrc ~/.vimrc
mkdir -p ~/.vim
ln -sf ~/dotfiles/.vim/coc-settings.json ~/.vim/coc-settings.json

# 2. vim-plug 자동 설치 (없는 경우)
if [ ! -f ~/.vim/autoload/plug.vim ]; then
  echo "Installing vim-plug..."
  curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

# 3. 플러그인 자동 설치 실행
vim +PlugInstall +qall

echo "Dotfiles setup complete!"
EOF

# 실행 권한 부여
chmod +x install.sh
