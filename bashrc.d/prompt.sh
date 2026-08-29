# =============================================
# ~/.dotfiles/bashrc.d/prompt.sh
# =============================================

# Prompt colors
RESET=$'\001\e[0m\002'

MAGENTA=$'\001\e[35m\002'
CYAN=$'\001\e[36m\002'
BRIGHT_RED=$'\001\e[91m\002'
BOLD_YELLOW=$'\001\e[3;33m\002'
GREEN=$'\001\e[32m\002'


# Git prompt
__prompt_git() {
    local status
    local branch
    local changes
    local state=''

    # Get branch and working-tree status in one Git invocation.
    status=$(git status --porcelain=v1 --branch 2>/dev/null) || return

    # Extract branch information.
    branch=${status%%$'\n'*}
    branch=${branch#\#\# }

    # Repository with no commits yet.
    if [[ $branch == "No commits yet on "* ]]; then
        branch=${branch#No commits yet on }

    # Detached HEAD.
    elif [[ $branch == "HEAD (no branch)"* ]]; then
        branch="detached"

    # Remove upstream information.
    else
        branch=${branch%%...*}
    fi

    # Extract file changes.
    if [[ "$status" == *$'\n'* ]]; then
        changes=${status#*$'\n'}

        # Unstaged changes.
        if [[ "$changes" =~ ^[[:space:]][MADRCU] ]]; then
            state+='!'
        fi

        # Staged changes.
        if [[ "$changes" =~ ^[MADRCU] ]]; then
            state+='+'
        fi

        # Untracked files.
        if [[ "$changes" =~ (^|$'\n')\?\? ]]; then
            state+='?'
        fi
    fi

    printf '%s\t%s' "$branch" "$state"
}

# Prompt state
__prompt_update() {
    local exit_status=$?

    local git_info
    local git_branch
    local git_state

    git_info=$(__prompt_git)

    if [[ -n $git_info ]]; then
        IFS=$'\t' read -r git_branch git_state <<< "$git_info"

        PS1_GIT="${GREEN}${git_branch}${RESET}"

        if [[ -n $git_state ]]; then
            PS1_GIT+=" ${BRIGHT_RED}${git_state}${RESET}"
        fi
    else
        PS1_GIT=''
    fi

    # Show the previous command's exit status only on failure.
    if (( exit_status != 0 )); then
        PS1_EXIT=" ${BRIGHT_RED}✗${exit_status}${RESET}"
    else
        PS1_EXIT=''
    fi
}

# Update prompt before every command line.
PROMPT_COMMAND+=(__prompt_update)

# Prompt
PS1="${MAGENTA}╭─${RESET} ${BOLD_YELLOW}\u@fedora${RESET} ${BRIGHT_RED}\w${RESET}\n${MAGENTA}╰─${RESET} \${PS1_GIT}\${PS1_EXIT} ${GREEN}❯${RESET} "

