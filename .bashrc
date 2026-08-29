# ================================================================
# ~/.bashrc
# ================================================================

# Non-interactive shell
[[ $- != *i* ]] && return


# Global shell configuration
if [[ -f /etc/bashrc ]]; then
  source /etc/bashrc
elif [[ -f /etc/bash.bashrc ]]; then
  source /etc/bash.bashrc
fi


# User environment
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  PATH="$HOME/.local/bin:$PATH"
fi

if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
  PATH="$HOME/bin:$PATH"
fi

export PATH


# User configuration
for rc in "$HOME/.dotfiles/bashrc.d/"*.sh; do
  [[ -f "$rc" ]] && source "$rc"
done

unset rc
