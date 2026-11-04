# familiar-ai.zsh — Atuin's AI prompt, answered by Emacs, on ß and Alt+ß.
#
# Atuin's own `?` (Atuin Hub) stays as it is.  These run the same inline
# TUI (`atuin ai inline --hook`) against the Atuin AI server inside the
# Emacs daemon (familiar-atuin.el): your Claude key, familiar's ledger.
#
#   ß      at an empty prompt, like Atuin's `?`: ask; Enter runs the
#          suggested command, Tab puts it on the prompt.  Anywhere else it
#          types ß.
#   Alt+ß  anywhere, like M-ß in Emacs: what's on the prompt is the
#          question (`atuin ai inline CMD' submits it at once): type
#          "nix files changed today", Alt+ß, and the answer replaces it.
#
# The widget mirrors `atuin ai init zsh` (18.18): `self-` prefix so
# bracketed-paste-magic keeps working, the same result protocol
# (__atuin_ai_print__/cancel/execute/insert), the same prompt padding.
# The token is read when used and passed in the environment of that one
# command (not on its command line, which other users can read).

typeset -g FAMILIAR_AI_URL=http://127.0.0.1:39391
typeset -g FAMILIAR_AI_TOKEN_FILE=${XDG_STATE_HOME:-$HOME/.local/state}/emacs/familiar-mcp-http-token

zmodload -F zsh/net/tcp b:ztcp 2>/dev/null

_familiar_ai_reset_prompt() {
    local -a _prompt_lines=("${(@f)${(%%)PROMPT}}")
    local -i _pad=$(( ${#_prompt_lines} - 1 ))
    (( _pad > 0 )) && printf '\n%.0s' {1..$_pad} >/dev/tty
    zle reset-prompt
}

# Is Emacs serving?  A TCP connect to the port: instant either way.
_familiar_ai_up() {
    [[ -r $FAMILIAR_AI_TOKEN_FILE ]] || return 1
    (( $+builtins[ztcp] )) || return 0          # can't tell: let atuin try
    local port=${FAMILIAR_AI_URL##*:}
    ztcp 127.0.0.1 $port 2>/dev/null || return 1
    ztcp -c $REPLY
}

# Ask; $1 is the command line to go along (empty for a fresh question).
_familiar_ai_ask() {
    if ! _familiar_ai_up; then
        zle -M "ß: Emacs isn't serving AI (M-x familiar-mcp-http-start)"
        return 1
    fi
    local output
    output=$(ATUIN_AI__ENDPOINT=$FAMILIAR_AI_URL ATUIN_AI__ENDPOINT_PROTOCOL=oss \
             ATUIN_AI__API_TOKEN=$(<$FAMILIAR_AI_TOKEN_FILE) \
             atuin ai inline --hook ${1:+"$1"} 3>&1 1>&2 2>&3)
    if [[ $output == __atuin_ai_print__:* ]]; then
        echo "${output#__atuin_ai_print__:}"
        BUFFER=$1                                # the line asked about, if any
        _familiar_ai_reset_prompt
    elif [[ $output == __atuin_ai_cancel__ ]]; then
        BUFFER=$1
        _familiar_ai_reset_prompt
    elif [[ $output == __atuin_ai_execute__:* ]]; then
        RBUFFER=""
        LBUFFER=${output#__atuin_ai_execute__:}
        _familiar_ai_reset_prompt
        zle accept-line
    elif [[ $output == __atuin_ai_insert__:* ]]; then
        RBUFFER=""
        LBUFFER=${output#__atuin_ai_insert__:}
        _familiar_ai_reset_prompt
    elif [[ -n $output ]]; then
        RBUFFER=""
        LBUFFER=$output
        _familiar_ai_reset_prompt
    else
        BUFFER=$1
        _familiar_ai_reset_prompt
    fi
}

# ß: only at an empty prompt, exactly like Atuin's `?`.
self-familiar-ai-sz() {
    if [[ -z "$BUFFER" || "$BUFFER" == "ß" ]]; then
        BUFFER=""
        _familiar_ai_ask || LBUFFER+=ß
    else
        # Not `zle self-insert': from a widget on a multibyte key it
        # inserted nothing (pty test: "straße" came out "strae").
        LBUFFER+=ß
    fi
}

# Alt+ß: the current line is the question.
familiar-ai-meta-sz() {
    local line=$BUFFER
    BUFFER=""
    _familiar_ai_ask "$line" || BUFFER=$line
}

zle -N self-familiar-ai-sz
zle -N familiar-ai-meta-sz
bindkey 'ß' self-familiar-ai-sz
bindkey '\eß' familiar-ai-meta-sz
