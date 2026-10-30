#!/usr/bin/env bash
# Batch tests and lint for home/doom/lisp, Doom not required.
#   run.sh          lint (byte-compile, warnings are errors) + ERT
#   run.sh test     ERT only
#   run.sh lint     lint only
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
lisp=$here/../lisp
emacs=${EMACS:-emacs}
# Modules that stand on their own under the shims; the rest need Doom loaded.
standalone=(+daemon.el +vellumory.el +workflow.el familiar/familiar.el)

lint() {
  "$emacs" -Q --batch -l "$here/shims.el" -l "$here/lint.el" \
    "${standalone[@]/#/$lisp/}" || return 1
  echo "lint: OK (${#standalone[@]} files)"
}

tests() {
  "$emacs" -Q --batch -l "$here/test-lisp.el" -l "$here/test-familiar.el" \
    -f ert-run-tests-batch-and-exit
}

case "${1:-all}" in
  lint) lint ;;
  test) tests ;;
  all) lint; tests ;;
esac
