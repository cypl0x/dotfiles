# familiar — standalone checks, no Doom needed.
#   make test     ERT
#   make compile  byte-compile, warnings are errors
# Dependencies (gptel; mcp-server-lib for familiar-mcp) come from -L dirs in
# LOAD_PATH, FAMILIAR_LOAD_PATH, or a Doom build (test/familiar-test-helper.el).

EMACS ?= emacs
LOAD_PATH ?=
EL := $(wildcard *.el)

.PHONY: test compile clean

test:
	$(EMACS) -Q --batch $(LOAD_PATH) -l test/familiar-test-helper.el \
	  -l test/familiar-test.el -l test/familiar-ask-test.el -f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch $(LOAD_PATH) -l test/familiar-test-helper.el \
	  --eval "(setq byte-compile-error-on-warn t)" -f batch-byte-compile $(EL)

clean:
	rm -f *.elc
