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
standalone=(+lua.el +org-links.el +transient.el +diagnostics.el +daemon.el +vellumory.el +workflow.el +tldr.el +proced.el +perf.el +usage.el +lsp-fallback.el +monet.el +persist.el +screenshot.el +format.el +vocab.el +docs.el +completion.el +org-lint.el +org-slash.el +org-cheatsheet.el +org-ai-capture.el +zoxide.el +tailscale.el +pide.el familiar/familiar.el familiar/familiar-mcp.el familiar/familiar-ask.el familiar/familiar-mcp-client.el familiar/familiar-mcp-http.el familiar/familiar-openai.el familiar/familiar-atuin.el familiar/familiar-history.el familiar/familiar-acp.el familiar/familiar-a2a.el familiar/familiar-rate.el familiar/familiar-prompts.el familiar/familiar-complete.el familiar/familiar-footprint.el well-formed/well-formed.el well-formed/well-formed-rules.el well-formed/well-formed-report.el well-formed/well-formed-menu.el)

lint() {
  "$emacs" -Q --batch -l "$here/shims.el" -l "$here/lint.el" \
    "${standalone[@]/#/$lisp/}" || return 1
  echo "lint: OK (${#standalone[@]} files)"
}

tests() {
  "$emacs" -Q --batch -l "$here/test-lisp.el" \
    -l "$lisp/familiar/test/familiar-test.el" -l "$lisp/familiar/test/familiar-ask-test.el" \
    -l "$lisp/well-formed/test/well-formed-test.el" \
    -f ert-run-tests-batch-and-exit
}

case "${1:-all}" in
lint) lint ;;
test) tests ;;
all)
  lint
  tests
  ;;
esac
