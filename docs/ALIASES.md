# Shell Aliases & Functions Reference

Complete guide to all aliases and functions available in this dotfiles configuration.

## Table of Contents

- [EZA (ls replacement)](#eza-ls-replacement)
- [BAT (cat replacement)](#bat-cat-replacement)
- [Navigation](#navigation)
- [File Operations](#file-operations)
- [Search & Find](#search--find)
- [Git](#git)
- [System Monitoring](#system-monitoring)
- [Network](#network)
- [Tmux](#tmux)
- [Utility Functions](#utility-functions)
- [NixOS Specific](#nixos-specific)

---

## EZA (ls replacement)

Modern replacement for `ls` with icons, git integration, and colors.

### Basic Listing

```bash
ls          # Basic list with icons and directories first
l           # Same as ls
ll          # Long format with git status
la          # Long format with hidden files
l.          # Hidden files only
```

### Sorted Views

```bash
llt         # Sort by modification time
lls         # Sort by size
lla         # Long format with all details and header
```

### Tree Views

```bash
lt          # Tree view of directory
lt1         # Tree view, 1 level deep
lt2         # Tree view, 2 levels deep
lt3         # Tree view, 3 levels deep
```

### Git Integration

```bash
lg          # Long list with git status, ignore git-ignored files
```

**Examples:**

```bash
# Show current directory with icons
ls

# Long format with git status
ll

# Tree view 2 levels deep
lt2

# Show only hidden files
l.
```

---

## BAT (cat replacement)

Syntax-highlighted file viewer with git integration.

```bash
cat <file>      # Syntax-highlighted cat
catp <file>     # Plain cat without decorations
catl <file>     # Cat with line numbers
```

**Examples:**

```bash
# View a Python file with syntax highlighting
cat script.py

# View without line numbers or decorations
catp config.txt

# View with line numbers
catl app.js
```

---

## Navigation

Quick directory navigation aliases.

```bash
..          # Go up one directory
...         # Go up two directories
....        # Go up three directories
.....       # Go up four directories

~           # Go to home directory
-           # Go to previous directory

# Quick shortcuts
dl          # cd ~/Downloads
doc         # cd ~/Documents
dt          # cd ~/Desktop
```

**Examples:**

```bash
# Go up two directories
...

# Go to previous directory
-

# Go to Downloads
dl
```

---

## File Operations

Enhanced file operation commands with safety features.

```bash
cp          # Copy with interactive prompt and verbose
mv          # Move with interactive prompt and verbose
rm          # Remove with interactive prompt (if >3 files)
mkdir       # Create directory with parents, verbose

# Always interactive variants
rmi         # rm with always-on interactive prompt
cpi         # cp with always-on interactive prompt
mvi         # mv with always-on interactive prompt
```

### Functions

#### mkcd - Make directory and cd into it

```bash
mkcd <directory>
```

**Example:**
```bash
mkcd project/src/components
# Creates nested directories and cd's into it
```

#### backup - Create timestamped backup

```bash
backup <file>
```

**Example:**
```bash
backup important-config.nix
# Creates: important-config.nix.backup-20251223-120500
```

#### extract - Extract any archive

```bash
extract <archive-file>
```

Supports: tar.gz, tar.bz2, tar.xz, zip, rar, 7z, and more.

**Example:**
```bash
extract archive.tar.gz
extract package.zip
```

#### targz - Create tar.gz archive

```bash
targz <file-or-directory>
```

**Example:**
```bash
targz myproject/
# Creates: myproject.tar.gz
```

#### zipf - Create zip archive

```bash
zipf <file-or-directory>
```

**Example:**
```bash
zipf documents/
# Creates: documents.zip
```

#### cpp - Copy with progress bar

```bash
cpp <source> <destination>
```

**Example:**
```bash
cpp large-file.iso /mnt/usb/
```

#### mvp - Move with progress bar

```bash
mvp <source> <destination>
```

---

## Search & Find

Enhanced search commands.

```bash
rg <pattern>        # Smart-case ripgrep with hidden files
rga <pattern>       # Search all files including ignored
```

### Functions

#### findlarge - Find large files

```bash
findlarge
```

Finds all files larger than 100MB in current directory.

#### findreplace - Find and replace in files

```bash
findreplace <search> <replace> [pattern]
```

**Example:**
```bash
findreplace "old_function" "new_function" "*.py"
```

#### filecount - Count files by extension

```bash
filecount [directory]
```

**Example:**
```bash
filecount .
# Output:
#   42 .nix
#   23 .md
#   15 .sh
```

---

## Git

Comprehensive git aliases for common operations.

### Status & Info

```bash
g           # git
gs          # git status
gl          # git log (oneline, graph)
gla         # git log --all (all branches)
gb          # git branch
```

### Adding & Committing

```bash
ga          # git add
gaa         # git add --all
gc          # git commit
gcm         # git commit -m "message"
```

### Pushing & Pulling

```bash
gp          # git push
gpl         # git pull
```

### Diff & Branches

```bash
gd          # git diff
gdc         # git diff --cached
gco         # git checkout
gcb         # git checkout -b (new branch)
```

### Stash

```bash
gst         # git stash
gstp        # git stash pop
```

**Examples:**

```bash
# Quick status check
gs

# Add all and commit
gaa
gcm "Add new feature"

# Create new branch and switch to it
gcb feature/new-widget

# View graphical log
gl
```

---

## System Monitoring

Monitor system resources and processes.

```bash
df          # Disk free (human readable)
du          # Disk usage (human readable)
free        # Memory info (human readable)
```

### Process Management

```bash
psg <name>      # Grep running processes
topcpu          # Top 10 CPU-consuming processes
topmem          # Top 10 memory-consuming processes
```

### Functions

#### psgrep - Find process by name

```bash
psgrep <process-name>
```

**Example:**
```bash
psgrep firefox
```

#### killps - Kill process by name

```bash
killps <process-name>
```

**Example:**
```bash
killps chrome
```

#### dusort - Show directory sizes sorted

```bash
dusort [directory]
```

**Example:**
```bash
dusort /var/log
# Shows all subdirectories sorted by size
```

#### sysinfo - Show system information

```bash
sysinfo
```

Shows: hostname, OS, kernel, uptime, CPU, memory, disk.

#### countfiles / countdirs - Count files or directories

```bash
countfiles [directory]
countdirs [directory]
```

---

## Network

Network utilities and information.

```bash
ports           # Show all listening ports
listening       # Show listening ports with process info
```

### IP Addresses

```bash
myip            # Get public IP address
myip4           # Get public IPv4 address
myip6           # Get public IPv6 address
localip         # Get local IP address
```

### Functions

#### lports - List listening ports

```bash
lports
```

Shows all ports the system is listening on.

#### weather - Quick weather

```bash
weather [location]
```

**Example:**
```bash
weather
weather London
weather "New York"
```

#### weatherfull - Detailed weather

```bash
weatherfull [location]
```

Shows full weather forecast.

---

## Tmux

Comprehensive tmux session and window management with 30+ aliases and functions.

### Basic Session Management

```bash
ta              # Attach to last session
tat <name>      # Attach to named session
tls             # List sessions
tnew <name>     # Create new session
tkill <name>    # Kill session
tka             # Kill all sessions except current
tkall           # Kill all sessions including server
tds             # Detach from session
trs <name>      # Rename current session
tss <name>      # Switch to session
```

### Window & Pane Management

```bash
tw              # New window
twn <name>      # New window with name
ts              # Split window
tsh             # Horizontal split
tsv             # Vertical split
trw <name>      # Rename current window
```

### Smart Functions

#### t - Quick launcher
```bash
t               # Attach to last or create default session
t dev           # Attach to 'dev' or create it
```

#### tn - Create or attach
```bash
tn work         # Create 'work' session or attach if exists
```

#### tlist - Detailed session list
```bash
tlist
# Shows:
#   dev: 3 windows, created 2h ago, attached: 1
#   work: 2 windows, created 1d ago, attached: 0
```

#### tdev - Development session layout
```bash
tdev            # Create 'dev' session with predefined layout
tdev myproject  # Create 'myproject' session

# Creates 4 windows:
# 1. editor   - Split for code and terminal
# 2. servers  - For dev servers
# 3. git      - For git operations
# 4. misc     - For other tasks
```

#### tmon - Monitoring session
```bash
tmon            # Create 'monitor' session with system monitoring

# Creates 4 panes showing:
# - htop (system resources)
# - journalctl (system logs)
# - ss (network stats)
# - Free pane for commands
```

#### tsendall - Send command to all panes
```bash
tsendall ls     # Run 'ls' in all panes of current window
tsendall pwd    # Run 'pwd' in all panes
```

#### tclone - Clone pane to new window
```bash
tclone          # Move current pane to its own window
```

#### tjoin - Join pane from another window
```bash
tjoin 2         # Join pane from window 2 to current window
```

#### tsave - Save session layout
```bash
tsave
# Saves to: ~/.tmux-session-<name>.txt
```

#### tswitch - Interactive session switcher (with fzf)
```bash
tswitch         # Fuzzy search and switch sessions
```

#### tsm - Session manager (with fzf)
```bash
tsm             # Interactive menu for session operations
# Options: New session, Attach, Kill, List
```

### Examples

**Quick start development:**
```bash
# Create dev session with layout
tdev myproject

# Or just use quick launcher
t myproject
```

**Monitor system:**
```bash
# Start monitoring session
tmon

# View in split panes: htop, logs, network stats
```

**Session management:**
```bash
# List all sessions
tlist

# Switch between sessions (with fzf)
tswitch

# Kill old sessions
tkill old-session

# Rename current session
trs new-name
```

**Window management:**
```bash
# Create new window with name
twn servers

# Rename current window
trw editing

# Split horizontally
tsh

# Split vertically
tsv
```

**Advanced:**
```bash
# Send command to all panes
tsendall "git pull"

# Save current layout
tsave

# Join window 3 to current
tjoin 3

# Clone pane to new window
tclone
```

### Tmux Key Bindings Quick Reference

These are default tmux bindings (prefix is Ctrl+b):

```
Prefix + c          # New window
Prefix + ,          # Rename window
Prefix + n          # Next window
Prefix + p          # Previous window
Prefix + %          # Split horizontal
Prefix + "          # Split vertical
Prefix + arrow      # Navigate panes
Prefix + x          # Kill pane
Prefix + d          # Detach session
Prefix + [          # Enter copy mode
Prefix + ]          # Paste
```

### Tips

1. **Use t for everything**: `t` attaches to last or creates default
2. **tdev for projects**: Automatic multi-window layout
3. **tmon for debugging**: Pre-configured monitoring setup
4. **tswitch for navigation**: Fuzzy find with fzf
5. **tsendall for batch**: Run commands across all panes

---

## Utility Functions

### serve - Quick HTTP server

```bash
serve [port]
```

Default port: 8000

**Example:**
```bash
serve 3000
# Starts HTTP server on port 3000
```

### note - Quick note taking

```bash
note [text]         # Add note with timestamp
note                # View all notes
```

**Example:**
```bash
note "Remember to backup before deployment"
note "Bug in user authentication module"
note  # View all notes
```

### path - Show PATH in readable format

```bash
path
```

Displays PATH variable with line numbers.

### json - Pretty print JSON

```bash
json '<json-string>'
echo '{"key":"value"}' | json
```

**Example:**
```bash
json '{"name":"Alice","age":30}'
cat data.json | json
```

### genpass - Generate random password

```bash
genpass [length]
```

Default length: 20

**Example:**
```bash
genpass 32
# Generates 32-character password
```

### uuid - Generate UUID

```bash
uuid
```

### man - Colored man pages

```bash
man <command>
```

Uses bat for syntax-highlighted man pages.

---

## NixOS Specific

See also: [README.md](../README.md) for complete NixOS functions.

### Quick Rebuild

```bash
nrs             # nixos-rebuild switch
nrb             # nixos-rebuild boot
nrt             # nixos-rebuild test
nrsv            # nixos-rebuild switch with verbose output
nrbs            # nixos-rebuild build (test without switching)
```

### Update & Maintenance

```bash
nixup                       # Update flake and rebuild
nixup-input <name>          # Update specific input
nixclean [days]             # Clean old generations (default: 30 days)
nixclean-all                # Clean all old generations
```

### Information

```bash
nixgen              # Show all generations
nixdu               # Show disk usage
nixdiff [g1] [g2]   # Compare generations
nixlist             # List installed packages
```

### Package Management

```bash
nixsearch <pkg>         # Search for package
nixinfo <pkg>           # Show package info
nixshell <pkg...>       # Enter shell with packages
nixrun <pkg> [cmd]      # Run package command
nixtry <pkg>            # Try package temporarily
```

### Flake Management

```bash
nixcheck            # Check flake for errors
nixshow             # Show flake outputs
```

---

## Miscellaneous

```bash
h               # History
j               # Jobs list
c               # Clear screen
q               # Exit shell

now             # Current date and time
nowutc          # Current UTC time
timestamp       # Unix timestamp

reload          # Reload shell configuration
```

---

## Color Enhancements

These commands are automatically colorized:

- `grep`, `egrep`, `fgrep` - Color in grep output
- `diff` - Colorized diff output

---

## Tips & Tricks

### Combine Commands

```bash
# Create project structure
mkcd myproject && mkcd src && mkcd components

# Quick git workflow
gaa && gcm "Update feature" && gp

# Find and extract
ll | grep archive
extract myarchive.tar.gz
```

### Using with FZF

Many commands work great with fzf:

```bash
# Fuzzy search and cat file
cat $(fzf)

# Fuzzy search and cd
cd $(find . -type d | fzf)

# Kill process with fuzzy search
killps $(ps aux | fzf | awk '{print $2}')
```

### Pipeline Examples

```bash
# Find large files and view details
findlarge | bat

# Show process tree
psg nginx | bat

# Pretty print JSON from curl
curl -s https://api.example.com/data | json

# Count file types in project
filecount ~/projects/myapp
```

---

## Customization

All aliases and functions are defined in `/etc/dotfiles/shell-aliases.sh`.

To add your own:

1. Edit `home/shell-aliases.sh` in your dotfiles
2. Rebuild: `nrs`
3. Reload shell: `reload` or start new shell

**Example custom alias:**

```bash
# Add to shell-aliases.sh
alias myalias='echo "Hello from my alias"'

# Then rebuild
nrs
```

---

## Cheatsheet Quick Reference

```bash
# File Navigation
ls, ll, la, lt      # List files (eza)
.., ..., cd -       # Navigate directories
mkcd <dir>          # Make and cd

# File Operations
cat, catp           # View files (bat)
backup <file>       # Create backup
extract <archive>   # Extract archive

# Git
gs, gaa, gcm        # Status, add all, commit
gp, gpl             # Push, pull
gl, gd              # Log, diff

# System
topcpu, topmem      # Top processes
sysinfo             # System info
dusort              # Directory sizes

# Network
myip, localip       # IP addresses
weather             # Current weather

# NixOS
nrs                 # Rebuild system
nixup               # Update system
nixsearch           # Search packages

# Utilities
serve               # HTTP server
genpass             # Generate password
note                # Take notes
json                # Pretty JSON
```

---

## See Also

- [README.md](../README.md) - Main documentation
- [USER-MANAGEMENT.md](USER-MANAGEMENT.md) - User and password management
- [Shell Aliases Source](../home/shell-aliases.sh) - Raw alias definitions
