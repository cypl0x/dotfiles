;;; lisp/+org-babel.el --- Org Babel, fixed where it breaks -*- lexical-binding: t; -*-
;;
;; Results that end in a blank line (`gh --help', most CLI help) failed to
;; come back from a src block: "Error reading results: Invalid search bound
;; (wrong side of point)".  Org reads shell output as a table
;; (`org-table-convert-region', separator `babel-auto'); when the region
;; ends at the start of an empty line, the separator regexp "^ *" matches
;; right at the region's end, inserts "| " there, and the next search
;; starts beyond its bound.  Still so in Org's main branch on 2026-11-05;
;; its 2026-10-30 fix covers empty output only, and isn't in the Org here
;; (9.8.9) yet.  Report drafted in
;; docs/upstream/org-table-convert-region-trailing-blank.org.
;;
;; Fix: the region ends after its last non-blank line (trailing blank lines
;; stay where they are, outside it); an empty region converts to nothing.
;; And shell blocks default to :results output (text, not a table).
;;
;;; Code:

(defun +org-babel-table-trim-a (fn beg end &rest rest)
  "Around `org-table-convert-region' (FN): drop trailing blank lines from
BEG..END; do nothing for a region with nothing in it.  REST as there."
  (let* ((lo (min beg end))
         (hi (save-excursion
               (goto-char (max beg end))
               (skip-chars-backward " \t\r\n" lo)
               (point))))
    (unless (= lo hi)
      (apply fn lo hi rest))))

(with-eval-after-load 'org-table
  (advice-add 'org-table-convert-region :around #'+org-babel-table-trim-a))

;; Shell blocks give their output as text (Org's default turns it into a
;; table, column per word: useless for help text and logs).  Per block,
;; :results value still makes a table.
(defvar org-babel-default-header-args:shell)
(defvar org-babel-default-header-args:sh)
(defvar org-babel-default-header-args:bash)
(with-eval-after-load 'ob-shell
  (dolist (var '(org-babel-default-header-args:shell org-babel-default-header-args:sh
                 org-babel-default-header-args:bash))
    (set var (cons '(:results . "output") (assq-delete-all :results (and (boundp var) (symbol-value var)))))))

(provide '+org-babel)
;;; +org-babel.el ends here
