;;; test/lint.el --- Byte-compile files with warnings as errors -*- lexical-binding: t; -*-
;; Usage: emacs -Q --batch -l shims.el -l lint.el FILE...
(require 'bytecomp)
(setq byte-compile-error-on-warn t
      byte-compile-dest-file-function
      (lambda (_) (make-temp-file "lint" nil ".elc")))
(let ((failed 0))
  (dolist (f command-line-args-left)
    (unless (ignore-errors (byte-compile-file f))
      (message "LINT FAILED: %s" f)
      (setq failed (1+ failed))))
  (setq command-line-args-left nil)
  (kill-emacs (if (zerop failed) 0 1)))
