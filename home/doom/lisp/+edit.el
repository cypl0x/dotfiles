;;; lisp/+edit.el --- Editing: grow the selection, cases, comments apart, syntax text objects -*- lexical-binding: t; -*-
;;
;;   v              (in visual state) grow the selection by syntax: symbol,
;;                  expression, statement, block …; v again grows, - shrinks
;;                  (expreg: tree-sitter nodes where there is a parser)
;;   SPC c ~        cycle the case of the symbol at point: foo_bar → FOO_BAR
;;                  → FooBar → fooBar → foo-bar (string-inflection)
;;   C-c '          the comment, string or doc block at point in its own
;;                  buffer, in its mode (Org's C-c ' for code; separedit)
;;
;; Text objects from tree-sitter, in modes with a parser (*-ts-mode), next
;; to Doom's f (function), a (argument) and c (comment):
;;
;;   C class   l loop   v conditional   A parameter   e entry (a Nix
;;   binding, a table field); which exist depends on the language's queries
;;   vae, diC, cil …;  [g KEY / ]g KEY: the previous / next one (also f, c)
;;
;;; Code:

(declare-function evil-textobj-tree-sitter-goto-textobj "ext:evil-textobj-tree-sitter"
                  (group &optional previous end query))

;;;; Grow the selection

;; Doom binds expand-region only without evil (config/default); with evil
;; it was on no key.  expreg instead: expand-region knows no tree-sitter and
;; went from a Lua symbol straight to the whole buffer.
(map! :v "v" #'expreg-expand
      :v "-" #'expreg-contract)

;;;; Cases

(map! :leader :desc "Cycle case (snake, CAMEL …)" "c ~" #'string-inflection-all-cycle)

;;;; A comment or string in its own buffer

(use-package! separedit
  :commands separedit
  :init
  (map! :map prog-mode-map "C-c '" #'separedit)
  :config
  ;; Doc comments are mostly prose: edit them as Markdown.
  (setq separedit-default-mode 'markdown-mode
        separedit-remove-trailing-spaces-in-comment t))

;;;; Text objects from tree-sitter

;; Doom's tools/tree-sitter had this commented out (for the old
;; tree-sitter-mode); here for treesit.  Group names must be literal: the
;; macro builds one text object per name.
(defvar +edit-goto-previous-map (make-sparse-keymap) "[g KEY: the previous one.")
(defvar +edit-goto-next-map (make-sparse-keymap) "]g KEY: the next one.")

(defvar evil-textobj-tree-sitter-major-mode-language-alist)

(defun +edit--register-language-h ()
  "This mode's tree-sitter language, for the text objects, if they don't
know it: their table missed modes like lua-ts-mode (\"stringp nil\")."
  (when-let* (((boundp 'evil-textobj-tree-sitter-major-mode-language-alist))
              ((not (alist-get major-mode evil-textobj-tree-sitter-major-mode-language-alist)))
              (parser (car (treesit-parser-list))))
    (push (cons major-mode (symbol-name (treesit-parser-language parser)))
          evil-textobj-tree-sitter-major-mode-language-alist)))

(defun +edit--goto (group previous)
  "A command going to the next (PREVIOUS: the previous) GROUP."
  (lambda () (interactive) (evil-textobj-tree-sitter-goto-textobj group previous)))

(use-package! evil-textobj-tree-sitter
  :after evil
  :config
  (add-hook 'after-change-major-mode-hook #'+edit--register-language-h)
  (map! (:map evil-inner-text-objects-map
         "e" (evil-textobj-tree-sitter-get-textobj "entry.inner")
         "C" (evil-textobj-tree-sitter-get-textobj "class.inner")
         "l" (evil-textobj-tree-sitter-get-textobj "loop.inner")
         "v" (evil-textobj-tree-sitter-get-textobj "conditional.inner")
         "A" (evil-textobj-tree-sitter-get-textobj "parameter.inner"))
        (:map evil-outer-text-objects-map
         "e" (evil-textobj-tree-sitter-get-textobj "entry.outer")
         "C" (evil-textobj-tree-sitter-get-textobj "class.outer")
         "l" (evil-textobj-tree-sitter-get-textobj "loop.outer")
         "v" (evil-textobj-tree-sitter-get-textobj "conditional.outer")
         "A" (evil-textobj-tree-sitter-get-textobj "parameter.outer")))
  (pcase-dolist (`(,key . ,group) '(("f" . "function.outer") ("e" . "entry.outer")
                                    ("C" . "class.outer") ("l" . "loop.outer")
                                    ("v" . "conditional.outer") ("A" . "parameter.outer")
                                    ("c" . "comment.outer")))
    (define-key +edit-goto-previous-map key (+edit--goto group t))
    (define-key +edit-goto-next-map key (+edit--goto group nil)))
  (map! :n "[g" +edit-goto-previous-map
        :n "]g" +edit-goto-next-map))

(provide '+edit)
;;; +edit.el ends here
