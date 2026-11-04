# shellcheck shell=bash
# glo — git log, one line per commit:
#
#   a1b2c3d 2026-11-04 14:46 Wolfhard   (HEAD -> main, origin/main) Subject (3f +12 -4)
#
# hash, date, author, refs (coloured like git's decorations), subject, and
# what the commit touched: files, lines added, lines deleted.  Binary files
# count as files without lines; a rename counts once.
#
# Packaged with writeShellApplication (home/common.nix): shellcheck runs at
# build time; git, gawk and less come with it.

usage() {
  cat <<'EOF'
Usage: glo [--color[=WHEN]] [--no-stat] [git log arguments...]

One line per commit: hash, date, author, refs, subject, (files +added -deleted).

  --color[=WHEN]  auto (default: on a terminal, unless NO_COLOR is set),
                  always, or never.  GLO_FORCE_COLOR=1 means always.
  --no-stat       leave out the file and line counts (faster in big repos)
  -h, --help      this help

Everything else goes to git log:  glo -20,  glo main..HEAD,  glo -- src/
On a terminal the output is paged with git's pager, as git log does.
EOF
}

color=auto
stat=1
args=()
while (($#)); do
  case $1 in
  -h | --help)
    usage
    exit 0
    ;;
  --color | --color=always) color=always ;;
  --color=never | --no-color) color=never ;;
  --color=auto) color=auto ;;
  --no-stat) stat=0 ;;
  --)
    args+=("$@")
    break
    ;;
  *) args+=("$1") ;;
  esac
  shift
done

tty=0
[[ -t 1 ]] && tty=1
if [[ $color == auto ]]; then
  if [[ -n ${GLO_FORCE_COLOR:-} ]] || { ((tty)) && [[ -z ${NO_COLOR:-} ]]; }; then
    color=always
  else
    color=never
  fi
fi

# Record separator before each commit, unit separator between its fields:
# neither can occur in a subject or a name.
format=$'%x1e%h%x1f%ad%x1f%an%x1f%D%x1f%s'
stat_args=()
((stat)) && stat_args=(--numstat)

render() {
  awk -v color="$([[ $color == always ]] && echo 1 || echo 0)" -v stat="$stat" '
    BEGIN {
      FS = "\037"
      if (color) {
        Y = "\033[33m"; D = "\033[2m"; C = "\033[36m"; B = "\033[1;36m"
        G = "\033[32m"; E = "\033[31m"; T = "\033[1;33m"; R = "\033[0m"
      }
    }
    # Refs as git decorates them: HEAD, local branches, remote ones, tags.
    function refs_of(s,    n, i, parts, out, r) {
      if (s == "") return ""
      n = split(s, parts, /, /)
      out = ""
      for (i = 1; i <= n; i++) {
        r = parts[i]
        if (r ~ /^HEAD -> /) { sub(/^HEAD -> /, "", r); r = B "HEAD" R D " -> " R G r R }
        else if (r == "HEAD") r = B r R
        else if (r ~ /^tag: /) r = T r R
        else if (r ~ /\//) r = E r R
        else r = G r R
        out = out (i > 1 ? D ", " R : "") r
      }
      return " " D "(" R out D ")" R
    }
    function emit() {
      if (!seen) return
      line = Y hash R " " D date R " " C author R refs_of(refs) " " subject
      if (stat && files) line = line " " D "(" files "f " R G "+" added R " " E "-" deleted R D ")" R
      print line
    }
    /^\036/ {
      emit()
      sub(/^\036/, "")
      hash = $1; date = $2; refs = $4; subject = $5
      # Fixed width, so subjects line up; "…" where a name is cut.
      author = length($3) > 14 ? substr($3, 1, 13) "…" : sprintf("%-14s", $3)
      files = added = deleted = 0
      seen = 1
      next
    }
    NF == 0 { next }
    {
      # numstat: added<TAB>deleted<TAB>path ("-" for binary files).
      split($0, f, "\t")
      if (f[1] ~ /^([0-9]+|-)$/ && f[2] ~ /^([0-9]+|-)$/) {
        files++
        if (f[1] != "-") added += f[1]
        if (f[2] != "-") deleted += f[2]
      }
    }
    END { emit() }'
}

run() {
  git -c color.ui=never log --date=format:'%Y-%m-%d %H:%M' --pretty=format:"$format" \
    "${stat_args[@]}" "${args[@]}" | render
}

if ((tty)); then
  pager=$(git var GIT_PAGER 2>/dev/null || echo less)
  # Like git: quit if it fits, keep colours, don't clear the screen.
  run | LESS=${LESS:-FRX} sh -c "$pager"
else
  run
fi
