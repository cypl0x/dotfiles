;;; lisp/+dtt.el --- Dependently typed language enhancements -*- lexical-binding: t; -*-
;;
;; Unified keybindings, workflow tools, and quality-of-life improvements
;; for Agda, Lean 4, Coq/Rocq, Idris 2, and F*.
;;
;;; Code:

;;;; Agda — Interactive proof development ────────────────────────────────────

(after! agda2
  ;; Ensure the agda-input method is available globally for Unicode.
  (add-hook 'agda2-mode-hook
            (lambda ()
              (set-input-method "Agda")))

  ;; Agda2-mode keybindings are set by the mode itself (C-c C-*).
  ;; Add Doom-style localleader bindings as aliases for discoverability.
  (map! :map agda2-mode-map
        :localleader
        (:prefix ("l" . "load/check")
         :desc "Load file"          "l" #'agda2-load)
        (:prefix ("g" . "goal")
         :desc "Goal type+context"  "," #'agda2-goal-and-context
         :desc "Goal type"          "t" #'agda2-goal-type
         :desc "Context"            "e" #'agda2-goal-and-context
         :desc "Inferred type"      "." #'agda2-goal-and-context-and-inferred)
        (:prefix ("r" . "refine")
         :desc "Refine"             "r" #'agda2-refine
         :desc "Auto (Mimer)"       "a" #'agda2-auto-maybe-all
         :desc "Give"               "SPC" #'agda2-give
         :desc "Case split"         "c" #'agda2-make-case)
        (:prefix ("n" . "navigate")
         :desc "Next goal"          "n" #'agda2-next-goal
         :desc "Previous goal"      "p" #'agda2-previous-goal)
        (:prefix ("s" . "search")
         :desc "Search about"       "s" #'agda2-search-about-toplevel
         :desc "Why in scope"       "w" #'agda2-why-in-scope-maybe-toplevel
         :desc "Normalize"          "n" #'agda2-compute-normalised-maybe-toplevel
         :desc "Infer type"         "d" #'agda2-infer-type-maybe-toplevel
         :desc "Constraints"        "=" #'agda2-show-constraints
         :desc "Module contents"    "o" #'agda2-module-contents-maybe-toplevel)))

;;;; Lean 4 — Continuous checking ────────────────────────────────────────────

;; Doom's `:lang lean' module with `+lsp' flag provides lean4-mode + eglot.
;; Add convenience bindings.

(after! lean4-mode
  (map! :map lean4-mode-map
        :localleader
        (:prefix ("i" . "info")
         :desc "Toggle info view"   "i" #'lean4-toggle-info
         :desc "Restart server"     "r" #'eglot-reconnect)
        (:prefix ("b" . "build")
         :desc "Lake build"         "b" #'lean4-lake-build)))

;;;; Coq/Rocq — Proof General + company-coq ─────────────────────────────────

(after! coq-mode
  ;; Ensure company-coq loads with PG.
  (add-hook 'coq-mode-hook #'company-coq-mode)

  (map! :map coq-mode-map
        :localleader
        (:prefix ("p" . "proof")
         :desc "Next step"          "n" #'proof-assert-next-command-interactive
         :desc "Undo step"          "u" #'proof-undo-last-successful-command
         :desc "To point"           "." #'proof-goto-point
         :desc "Retract"            "r" #'proof-retract-buffer
         :desc "Process buffer"     "b" #'proof-process-buffer)
        (:prefix ("s" . "search")
         :desc "Search"             "s" #'coq-SearchAbout
         :desc "Check"              "c" #'coq-Check
         :desc "Print"              "p" #'coq-Print
         :desc "About"              "a" #'coq-About)))

;;;; Idris 2 ─────────────────────────────────────────────────────────────────

(after! idris2-mode
  (map! :map idris2-mode-map
        :localleader
        (:prefix ("l" . "load")
         :desc "Load file"          "l" #'idris2-load-file)
        (:prefix ("r" . "refine")
         :desc "Case split"         "c" #'idris2-case-dwim
         :desc "Add clause"         "s" #'idris2-add-clause
         :desc "Proof search"       "a" #'idris2-proof-search
         :desc "Make lemma"         "e" #'idris2-make-lemma
         :desc "Make with"          "w" #'idris2-make-with-block)
        (:prefix ("t" . "type")
         :desc "Type at point"      "t" #'idris2-type-at-point
         :desc "Type search"        "s" #'idris2-type-search
         :desc "Docs at point"      "d" #'idris2-docs-at-point)))

;;;; F* ──────────────────────────────────────────────────────────────────────

(after! fstar-mode
  (map! :map fstar-mode-map
        :localleader
        (:prefix ("p" . "proof")
         :desc "Next step"          "n" #'fstar-subp-advance-next
         :desc "Retract"            "u" #'fstar-subp-retract
         :desc "To point"           "." #'fstar-subp-advance-or-retract-to-point
         :desc "Lax check"          "l" #'fstar-subp-advance-next-lax)))

;;;; ob-lean — Org-babel for Lean 4 ─────────────────────────────────────────

;; ob-lean — Org-babel for Lean 4 (requires doom sync to install).
(when (locate-library "ob-lean")
  (after! org
    (add-to-list 'org-babel-load-languages '(lean . t) t)))

;;;; Unicode input — global availability ─────────────────────────────────────

(defun +dtt/toggle-agda-input ()
  "Toggle Agda Unicode input method globally.
Useful outside Agda buffers for writing type theory in org-mode, etc."
  (interactive)
  (if (string= current-input-method "Agda")
      (deactivate-input-method)
    (set-input-method "Agda"))
  (message "Agda input: %s" (if current-input-method "ON" "OFF")))

;;;; Proof status overview ───────────────────────────────────────────────────

(defun +dtt/proof-status ()
  "Show a summary of proof assistant buffers and their state."
  (interactive)
  (let ((buf (get-buffer-create "*Proof Status*"))
        (entries nil))
    ;; Collect proof-relevant buffers.
    (dolist (b (buffer-list))
      (with-current-buffer b
        (when (or (derived-mode-p 'agda2-mode)
                  (derived-mode-p 'coq-mode)
                  (derived-mode-p 'lean4-mode)
                  (derived-mode-p 'idris2-mode)
                  (derived-mode-p 'fstar-mode))
          (push (list (buffer-name)
                      (symbol-name major-mode)
                      (if (buffer-modified-p) "modified" "saved")
                      (or (buffer-file-name) "no file"))
                entries))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize "Proof Assistant Buffers\n\n"
                            'face '(:height 1.3 :weight bold)))
        (if (null entries)
            (insert "No proof buffers open.\n")
          (insert (propertize
                   (format "%-25s %-18s %-10s %s\n" "Buffer" "Mode" "State" "File")
                   'face '(:weight bold))
                  (make-string 80 ?─) "\n")
          (dolist (e (reverse entries))
            (insert (format "%-25s %-18s %-10s %s\n"
                            (nth 0 e) (nth 1 e) (nth 2 e) (nth 3 e))))))
      (goto-char (point-min))
      (view-mode 1))
    (pop-to-buffer buf)))

;;;; Transient — DTT dispatch ────────────────────────────────────────────────

(transient-define-prefix +dtt/transient ()
    "Dependently Typed Languages dispatch."
    ["Navigation"
     ("u" "Toggle Agda Unicode input" +dtt/toggle-agda-input)
     ("s" "Proof status overview"     +dtt/proof-status)]
    ["Open"
     ("a" "Agda file"  (lambda () (interactive) (find-file (read-file-name "Agda file: " nil nil nil nil (lambda (f) (string-suffix-p ".agda" f))))))
     ("l" "Lean file"  (lambda () (interactive) (find-file (read-file-name "Lean file: " nil nil nil nil (lambda (f) (string-suffix-p ".lean" f))))))
     ("c" "Coq file"   (lambda () (interactive) (find-file (read-file-name "Coq file: " nil nil nil nil (lambda (f) (string-suffix-p ".v" f))))))
     ("i" "Idris file" (lambda () (interactive) (find-file (read-file-name "Idris file: " nil nil nil nil (lambda (f) (string-suffix-p ".idr" f))))))])
;;;; Keybindings ─────────────────────────────────────────────────────────────

(map! :leader
      (:prefix ("D" . "DTT")
       :desc "DTT menu"              "D" #'+dtt/transient
       :desc "Agda Unicode toggle"   "u" #'+dtt/toggle-agda-input
       :desc "Proof status"          "s" #'+dtt/proof-status))

(provide '+dtt)
;;; +dtt.el ends here
