;;; familiar-test-helper.el --- Load path for familiar's tests -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; The tests need gptel (and, for a few, mcp-server-lib, mcp.el and node).  They are found
;; on `load-path' as given (emacs -L), in FAMILIAR_LOAD_PATH (colon
;; separated), or in a Doom Emacs build next to this checkout's config.
;; familiar itself is the parent directory.
;;
;;; Code:

(require 'ert)

(let ((here (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." here))
  (dolist (dir (split-string (or (getenv "FAMILIAR_LOAD_PATH") "") ":" t))
    (add-to-list 'load-path (expand-file-name dir)))
  ;; Doom's straight build, when this lives in a Doom config.
  ;; Each package not found otherwise (jsonrpc: the newer one Doom builds).
  (when-let* ((doom (or (getenv "EMACSDIR") (expand-file-name "~/.config/emacs/")))
              (build (car (file-expand-wildcards
                           (expand-file-name (concat ".local/straight/build-" emacs-version) doom)))))
    (dolist (pkg '("gptel" "transient" "compat" "cond-let" "llama" "mcp-server-lib" "mcp" "jsonrpc" "package-lint"))
      (let ((dir (expand-file-name pkg build)))
        (when (and (file-directory-p dir)
                   (or (equal pkg "jsonrpc") (not (locate-library pkg))))
          (add-to-list 'load-path dir))))))

(provide 'familiar-test-helper)
;;; familiar-test-helper.el ends here
