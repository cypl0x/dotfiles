#!/usr/bin/env bash
# Shell aliases and functions for bash/zsh
# Source this file from your shell configuration

# ============================================================================
# EZA (Modern ls replacement) Aliases
# ============================================================================

# Basic ls replacements
alias ls='eza --icons --group-directories-first'
alias l='eza --icons --group-directories-first'
alias ll='eza -l --icons --group-directories-first --git'
alias la='eza -la --icons --group-directories-first --git'
alias lt='eza -T --icons --group-directories-first'  # Tree view
alias l.='eza -la --icons | grep "^\."'  # Hidden files only

# Long format variations
alias lla='eza -la --icons --group-directories-first --git --header'
alias llt='eza -l --icons --group-directories-first --git --sort=modified'  # Sort by time
alias lls='eza -l --icons --group-directories-first --git --sort=size'      # Sort by size

# Tree views
alias lt1='eza -T --icons --group-directories-first --level=1'
alias lt2='eza -T --icons --group-directories-first --level=2'
alias lt3='eza -T --icons --group-directories-first --level=3'

# Git-aware ls
alias lg='eza -la --icons --group-directories-first --git --git-ignore'

# ============================================================================
# BAT (Better cat) Aliases
# ============================================================================

alias cat='bat --style=auto'
alias catp='bat --style=plain'  # Plain cat without decorations
alias catl='bat --style=numbers'  # With line numbers

# ============================================================================
# Navigation Aliases
# ============================================================================

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

alias ~='cd ~'
alias -- -='cd -'  # Go to previous directory

# Quick directory shortcuts
alias dl='cd ~/Downloads'
alias doc='cd ~/Documents'
alias dt='cd ~/Desktop'

# ============================================================================
# File Operations
# ============================================================================

alias cp='cp -iv'  # Interactive, verbose
alias mv='mv -iv'  # Interactive, verbose
alias rm='rm -Iv'  # Interactive, verbose (prompt if >3 files)
alias mkdir='mkdir -pv'  # Create parent dirs, verbose

# Safe alternatives
alias rmi='rm -i'  # Always prompt
alias cpi='cp -i'  # Always prompt
alias mvi='mv -i'  # Always prompt

# ============================================================================
# Search & Find
# ============================================================================

alias rg='rg --smart-case --hidden'
alias rga='rg --smart-case --hidden --no-ignore'  # Search all files including ignored

# Find large files
alias findlarge='find . -type f -size +100M -exec ls -lh {} \; 2>/dev/null'

# ============================================================================
# Git Aliases
# ============================================================================

alias g='git'
alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gd='git diff'
alias gdc='git diff --cached'
alias gl='git log --oneline --decorate --graph'
alias gla='git log --oneline --decorate --graph --all'
alias gb='git branch'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gst='git stash'
alias gstp='git stash pop'

# ============================================================================
# System Monitoring
# ============================================================================

alias df='df -h'  # Human readable
alias du='du -h'  # Human readable
alias free='free -h'  # Human readable

# Process management
alias psg='ps aux | grep -v grep | grep -i -e VSZ -e'  # Grep processes
alias topcpu='ps aux | sort -nrk 3,3 | head -n 10'  # Top CPU processes
alias topmem='ps aux | sort -nrk 4,4 | head -n 10'  # Top memory processes

# ============================================================================
# Network
# ============================================================================

alias ports='netstat -tulanp'  # Show listening ports
alias listening='lsof -i -P | grep LISTEN'

# Get public IP
alias myip='curl -s ifconfig.me'
alias myip4='curl -s -4 ifconfig.me'
alias myip6='curl -s -6 ifconfig.me'

# Local IP
alias localip="ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1"

# ============================================================================
# Tmux Aliases & Functions
# ============================================================================

# Basic tmux aliases
alias ta='tmux attach'
alias tat='tmux attach -t'
alias tls='tmux ls'
alias tnew='tmux new -s'
alias tkill='tmux kill-session -t'
alias tka='tmux kill-session -a'  # Kill all sessions except current
alias tkall='tmux kill-server'    # Kill all sessions including server

# Tmux window/pane management
alias tw='tmux new-window'
alias twn='tmux new-window -n'    # New window with name
alias ts='tmux split-window'
alias tsh='tmux split-window -h'  # Horizontal split
alias tsv='tmux split-window -v'  # Vertical split

# Tmux session management
alias trs='tmux rename-session'
alias tds='tmux detach'
alias tss='tmux switch-client -t'  # Switch session

# Quick tmux launcher - attach to existing or create new
t() {
  if [ -z "$1" ]; then
    # No argument - attach to last session or create default
    tmux attach 2>/dev/null || tmux new -s default
  else
    # Attach to named session or create it
    tmux attach -t "$1" 2>/dev/null || tmux new -s "$1"
  fi
}

# Create or attach to named session
tn() {
  if [ -z "$1" ]; then
    echo "Usage: tn <session-name>"
    return 1
  fi
  tmux new -s "$1" || tmux attach -t "$1"
}

# List tmux sessions with details
tlist() {
  if ! tmux list-sessions &>/dev/null; then
    echo "No tmux sessions running"
    return 0
  fi

  echo "=== Tmux Sessions ==="
  tmux list-sessions -F "#{session_name}: #{session_windows} windows, created #{session_created_string}, attached: #{session_attached}" | \
    while IFS= read -r line; do
      echo "  $line"
    done
}

# Create session with predefined layout
tdev() {
  local session_name=${1:-dev}

  # Create session if it doesn't exist
  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    # Create new session
    tmux new-session -d -s "$session_name" -n editor

    # Window 1: editor (split for main code and terminal)
    tmux split-window -h -t "$session_name:1"
    tmux split-window -v -t "$session_name:1.2"

    # Window 2: servers (for running dev servers)
    tmux new-window -t "$session_name" -n servers

    # Window 3: git (for git operations)
    tmux new-window -t "$session_name" -n git

    # Window 4: misc (for other tasks)
    tmux new-window -t "$session_name" -n misc

    # Select first window
    tmux select-window -t "$session_name:1"

    echo "Created development session: $session_name"
  fi

  # Attach to session
  tmux attach -t "$session_name"
}

# Create monitoring session layout
tmon() {
  local session_name=${1:-monitor}

  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    # Create session with monitoring layout
    tmux new-session -d -s "$session_name" -n system

    # Split for htop, logs, and network
    tmux split-window -v -t "$session_name:1"
    tmux split-window -h -t "$session_name:1.1"
    tmux split-window -h -t "$session_name:1.2"

    # Send commands to each pane
    tmux send-keys -t "$session_name:1.1" 'htop' C-m
    tmux send-keys -t "$session_name:1.2" 'journalctl -f' C-m
    tmux send-keys -t "$session_name:1.3" 'watch -n 2 ss -s' C-m

    echo "Created monitoring session: $session_name"
  fi

  tmux attach -t "$session_name"
}

# Rename current tmux window
trw() {
  if [ -z "$TMUX" ]; then
    echo "Not in a tmux session"
    return 1
  fi

  if [ -z "$1" ]; then
    echo "Usage: trw <window-name>"
    return 1
  fi

  tmux rename-window "$1"
}

# Send command to all panes in current window
tsendall() {
  if [ -z "$TMUX" ]; then
    echo "Not in a tmux session"
    return 1
  fi

  if [ -z "$1" ]; then
    echo "Usage: tsendall <command>"
    return 1
  fi

  tmux setw synchronize-panes on
  tmux send-keys "$*" C-m
  tmux setw synchronize-panes off
}

# Clone current pane to new window
tclone() {
  if [ -z "$TMUX" ]; then
    echo "Not in a tmux session"
    return 1
  fi

  tmux break-pane
}

# Join pane from another window
tjoin() {
  if [ -z "$TMUX" ]; then
    echo "Not in a tmux session"
    return 1
  fi

  if [ -z "$1" ]; then
    echo "Usage: tjoin <source-window>"
    echo "Example: tjoin 2  (joins window 2's pane to current window)"
    return 1
  fi

  tmux join-pane -s "$1"
}

# Save tmux session layout
tsave() {
  if [ -z "$TMUX" ]; then
    echo "Not in a tmux session"
    return 1
  fi

  local session_name=$(tmux display-message -p '#S')
  local save_file="$HOME/.tmux-session-$session_name.txt"

  tmux list-windows -F "#{window_index} #{window_name} #{pane_current_path}" > "$save_file"
  echo "Session layout saved to: $save_file"
}

# Quick session switcher with fzf (if available)
tswitch() {
  if ! command -v fzf &>/dev/null; then
    # Fallback to simple list if fzf not available
    echo "Available sessions:"
    tmux list-sessions -F "#{session_name}"
    return 0
  fi

  local session
  session=$(tmux list-sessions -F "#{session_name}" | fzf --height 40% --reverse)

  if [ -n "$session" ]; then
    if [ -z "$TMUX" ]; then
      tmux attach -t "$session"
    else
      tmux switch-client -t "$session"
    fi
  fi
}

# Tmux session manager - interactive
tsm() {
  if ! command -v fzf &>/dev/null; then
    echo "This function requires fzf. Use 'tlist' to list sessions."
    return 1
  fi

  local choice
  choice=$(echo -e "New session\nAttach to session\nKill session\nList sessions" | fzf --height 40% --reverse)

  case "$choice" in
    "New session")
      echo -n "Session name: "
      read session_name
      tnew "$session_name"
      ;;
    "Attach to session")
      tswitch
      ;;
    "Kill session")
      local session
      session=$(tmux list-sessions -F "#{session_name}" | fzf --height 40% --reverse)
      if [ -n "$session" ]; then
        tmux kill-session -t "$session"
        echo "Killed session: $session"
      fi
      ;;
    "List sessions")
      tlist
      ;;
  esac
}

# ============================================================================
# Utility Functions
# ============================================================================

# Create directory and cd into it
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Extract various archive types
extract() {
  if [ -z "$1" ]; then
    echo "Usage: extract <archive-file>"
    return 1
  fi

  if [ ! -f "$1" ]; then
    echo "Error: '$1' is not a valid file"
    return 1
  fi

  case "$1" in
    *.tar.bz2)   tar xjf "$1"     ;;
    *.tar.gz)    tar xzf "$1"     ;;
    *.tar.xz)    tar xJf "$1"     ;;
    *.bz2)       bunzip2 "$1"     ;;
    *.rar)       unrar x "$1"     ;;
    *.gz)        gunzip "$1"      ;;
    *.tar)       tar xf "$1"      ;;
    *.tbz2)      tar xjf "$1"     ;;
    *.tgz)       tar xzf "$1"     ;;
    *.zip)       unzip "$1"       ;;
    *.Z)         uncompress "$1"  ;;
    *.7z)        7z x "$1"        ;;
    *)           echo "Error: '$1' cannot be extracted via extract()" ;;
  esac
}

# Create a backup of a file
backup() {
  if [ -z "$1" ]; then
    echo "Usage: backup <file>"
    return 1
  fi
  cp "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
}

# Quick web server in current directory
serve() {
  local port=${1:-8000}
  python3 -m http.server "$port"
}

# Find process by name
psgrep() {
  if [ -z "$1" ]; then
    echo "Usage: psgrep <process-name>"
    return 1
  fi
  ps aux | grep -v grep | grep -i "$1"
}

# Kill process by name
killps() {
  if [ -z "$1" ]; then
    echo "Usage: killps <process-name>"
    return 1
  fi
  local pid=$(ps aux | grep -v grep | grep -i "$1" | awk '{print $2}')
  if [ -n "$pid" ]; then
    echo "Killing process: $pid"
    kill "$pid"
  else
    echo "No process found matching: $1"
  fi
}

# Show directory size sorted
dusort() {
  du -h --max-depth=1 "$@" | sort -hr
}

# Create a tar.gz archive
targz() {
  if [ -z "$1" ]; then
    echo "Usage: targz <file-or-directory>"
    return 1
  fi
  tar -czf "${1%/}.tar.gz" "$1"
}

# Create a zip archive
zipf() {
  if [ -z "$1" ]; then
    echo "Usage: zipf <file-or-directory>"
    return 1
  fi
  zip -r "${1%/}.zip" "$1"
}

# Weather
weather() {
  local location=${1:-}
  curl -s "wttr.in/${location}?format=3"
}

# Detailed weather
weatherfull() {
  local location=${1:-}
  curl -s "wttr.in/${location}"
}

# Show PATH in readable format
path() {
  echo "$PATH" | tr ':' '\n' | nl
}

# Count files in directory
countfiles() {
  find "${1:-.}" -type f | wc -l
}

# Count directories
countdirs() {
  find "${1:-.}" -type d | wc -l
}

# Quick note taking
note() {
  local note_file="$HOME/notes.txt"
  if [ -z "$1" ]; then
    bat "$note_file"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$note_file"
    echo "Note added: $*"
  fi
}

# Copy with progress bar
cpp() {
  rsync -ah --info=progress2 "$@"
}

# Move with progress bar
mvp() {
  rsync -ah --info=progress2 --remove-source-files "$@"
}

# Find and replace in files
findreplace() {
  if [ $# -lt 2 ]; then
    echo "Usage: findreplace <search-pattern> <replace-text> [file-pattern]"
    return 1
  fi
  local search="$1"
  local replace="$2"
  local pattern="${3:-*}"

  find . -type f -name "$pattern" -exec sed -i "s/$search/$replace/g" {} +
}

# Show file count by extension
filecount() {
  find "${1:-.}" -type f | sed -n 's/..*\.//p' | sort | uniq -c | sort -rn
}

# Colored man pages using bat
man() {
  MANPAGER="sh -c 'col -bx | bat -l man -p'" command man "$@"
}

# ============================================================================
# System Information Functions
# ============================================================================

# Show system info
sysinfo() {
  echo "=== System Information ==="
  echo "Hostname: $(hostname)"
  echo "OS: $(uname -s)"
  echo "Kernel: $(uname -r)"
  echo "Uptime: $(uptime -p)"
  echo "CPU: $(nproc) cores"
  echo "Memory: $(free -h | awk '/^Mem:/ {print $3 " / " $2}')"
  echo "Disk: $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 " used)"}')"
}

# Show listening ports
lports() {
  echo "=== Listening Ports ==="
  netstat -tuln | grep LISTEN
}

# ============================================================================
# Development Helpers
# ============================================================================

# Pretty JSON
json() {
  if [ -t 0 ]; then
    # Argument provided
    echo "$1" | python3 -m json.tool | bat -l json
  else
    # Piped input
    python3 -m json.tool | bat -l json
  fi
}

# Generate random password
genpass() {
  local length=${1:-20}
  LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"; echo
}

# Generate UUID
uuid() {
  cat /proc/sys/kernel/random/uuid
}

# ============================================================================
# Misc Aliases
# ============================================================================

alias h='history'
alias j='jobs -l'
alias c='clear'
alias q='exit'

# Date/time
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias nowutc='date -u +"%Y-%m-%d %H:%M:%S UTC"'
alias timestamp='date +%s'

# Reload shell
alias reload='exec $SHELL -l'

# ============================================================================
# Colorful helpers
# ============================================================================

# Add color to common commands if not already aliased
if command -v grep &> /dev/null; then
  alias grep='grep --color=auto'
  alias egrep='egrep --color=auto'
  alias fgrep='fgrep --color=auto'
fi

if command -v diff &> /dev/null; then
  alias diff='diff --color=auto'
fi

# ============================================================================
# Platform-specific
# ============================================================================

# Linux-specific
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
  alias open='xdg-open'
fi
