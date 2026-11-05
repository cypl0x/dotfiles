#!/usr/bin/env bash
# melpa-check.sh: what MELPA's review asks of familiar, in one go:
# package-lint (main file familiar.el), checkdoc, and a byte-compile with
# warnings as errors.  Packages come from `load-path' as given (emacs -L
# through EMACSLOADPATH), FAMILIAR_LOAD_PATH, or a Doom build (see
# familiar-test-helper.el).  Exit 1 on any finding.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
emacs=${EMACS:-emacs}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$here"/*.el "$work"/
cd "$work"
helper="$here/test/familiar-test-helper.el"
status=0

echo "== package-lint"
if ! "$emacs" -Q --batch -l "$helper" --eval "(add-to-list 'load-path \"$work\")" \
  --eval "(progn (require 'package-lint) (setq package-lint-main-file \"familiar.el\"))" \
  -f package-lint-batch-and-exit ./*.el 2>&1 |
  grep -v "is not installable" | grep -E "(error|warning):"; then
  echo "clean"
else
  status=1
fi

echo "== checkdoc"
cat >"$work/.checkdoc-all.el" <<'EOF'
;;; -*- lexical-binding: t; -*-
(require 'checkdoc)
(setq checkdoc-diagnostic-buffer "*checkdoc*")
;; On explicitly: whether it is on otherwise differs between Emacs builds,
;; and CI's checkdoc runs it.
(setq checkdoc-verb-check-experimental-flag t)
(dolist (f (directory-files "." nil "\\.el\\'"))
  (with-current-buffer (find-file-noselect f)
    (ignore-errors (checkdoc-current-buffer t))))
(with-current-buffer (get-buffer-create "*checkdoc*") (princ (buffer-string)))
EOF
found=$("$emacs" -Q --batch -l "$helper" --eval "(add-to-list 'load-path \"$work\")" \
  -l "$work/.checkdoc-all.el" 2>&1 | grep -E '^[a-z-]+\.el:[0-9]+' || true)
if [ -n "$found" ]; then
  echo "$found"
  status=1
else
  echo "clean"
fi

echo "== byte-compile (warnings as errors)"
if "$emacs" -Q --batch -l "$helper" --eval "(add-to-list 'load-path \"$work\")" \
  --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile ./*.el; then
  echo "clean"
else
  status=1
fi

exit $status
