#!/usr/bin/env bash
# $PS1 - The default interactive prompt string.
# You can't set the nice debug options in a script intended to be sourced for an interactive prompt because any command that fails will cause the interactive shell to exit.
#set -Eeuo pipefail

# This one does not have the cool line characters:
# export PS1="\[\]\n\[\e[30;1m\]\[\016\]l\[\017\](\[\e[34;1m\]\u@\h\[\e[30;1m\])-(\[\e[34;1m\]\j\[\e[30;1m\])-(\[\e[34;1m\]\@ \d\[\e[30;1m\])->\[\e[30;1m\]\n\[\016\]m\[\017\]-(\[\[\e[32;1m\]\w\[\e[30;1m\])-(\[\e[32;1m\]$(/bin/ls -1 | /usr/bin/wc -l | /bin/sed 's: ::g') files, $(/bin/ls -lah | /bin/grep -m 1 total | /bin/sed 's/total //')b\[\e[30;1m\])--> \[\e[0m\]\[\]"
# According to this, I can modify it so here's a try:
# https://superuser.com/questions/743889/what-016-017-in-bash-prompt-how-can-i-make-it-correct-in-terminal 
# export PS1="\[\]\n\[\e[30;1m\]\[\033(0\]l\[\033(B\](\[\e[34;1m\]\u@\h\[\e[30;1m\])-(\[\e[34;1m\]\j\[\e[30;1m\])\
# -(\[\e[34;1m\]\@ \d\[\e[30;1m\])->\[\e[30;1m\]\n\[\033(0\]m\[\033(B\]-(\[\[\e[32;1m\]\w\[\e[30;1m\])-(\[\e[32;1m\]\
# $(/bin/ls -1 | /usr/bin/wc -l | /bin/sed 's: ::g') files, \
# $(/bin/ls -lah | /bin/grep -m 1 total \
# | /bin/sed 's/total //'\
# )b\
# $()\
# \[\e[30;1m\])--> \[\e[0m\]\[\]"

# This is the content of the codespaces .bashrc bash prompt configuration:
# bash theme - partly inspired by https://github.com/ohmyzsh/ohmyzsh/blob/master/themes/robbyrussell.zsh-theme
#heredoc=$(cat << 'EOF'
__bash_prompt() {
    local userpart='`export XIT=$? \
        && [ ! -z "${GITHUB_USER}" ] && echo -n "\[\033[0;32m\]@${GITHUB_USER} " || echo -n "\[\033[0;32m\]\u " \
        && [ "$XIT" -ne "0" ] && echo -n "\[\033[1;31m\]➜" || echo -n "\[\033[0m\]➜"`'
    local gitbranch='`\
        if [ "$(git config --get devcontainers-theme.hide-status 2>/dev/null)" != 1 ] && [ "$(git config --get codespaces-theme.hide-status 2>/dev/null)" != 1 ]; then \
            export BRANCH=$(git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git --no-optional-locks rev-parse --short HEAD 2>/dev/null); \
            if [ "${BRANCH}" != "" ]; then \
                echo -n "\[\033[0;36m\](\[\033[1;31m\]${BRANCH}" \
                && if [ "$(git config --get devcontainers-theme.show-dirty 2>/dev/null)" = 1 ] && \
                    git --no-optional-locks ls-files --error-unmatch -m --directory --no-empty-directory -o --exclude-standard ":/*" > /dev/null 2>&1; then \
                        echo -n " \[\033[1;33m\]✗"; \
                fi \
                && echo -n "\[\033[0;36m\]) "; \
            fi; \
        fi`'
    local lightblue='\[\033[1;34m\]'
    local removecolor='\[\033[0m\]'
    PS1="${userpart} ${lightblue}\w ${gitbranch}${removecolor}\$ "

    export PS1="\[\]\n\[\e[30;1m\]\[\033(0\]l\[\033(B\](\[\e[34;1m\]\u@\h\[\e[30;1m\])-(\[\e[34;1m\]\j\[\e[30;1m\])\
-(\[\e[34;1m\]\@ \d\[\e[30;1m\])->\[\e[30;1m\]\n\[\033(0\]m\[\033(B\]-(\[\[\e[32;1m\]\w\[\e[30;1m\])-(\[\e[32;1m\]\
$(/bin/ls -1 | /usr/bin/wc -l | /bin/sed 's: ::g') files, \
$(/bin/ls -lah | /bin/grep -m 1 total \
| /bin/sed 's/total //'\
)b\
 ${gitbranch}\
\[\e[30;1m\])--> \[\e[0m\]\[\]"


    # unset -f __bash_prompt
}
__bash_prompt
export PROMPT_DIRTRIM=4
#EOF
#)

#$(${heredoc})

