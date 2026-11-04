;;; lisp/+pide.el --- Isabelle/PIDE-style panels for any language server -*- lexical-binding: t; -*-
;;
;; From the task list: Isabelle PIDE's way of working, for Lean, Rust, Zig,
;; Nix and the rest.  Isabelle/jEdit checks continuously and shows what it
;; knows in docked panels that follow the cursor: Output (state and messages
;; here), Theories (what's checked), Sidekick (the document's outline).  The
;; knowledge comes from language servers here (eglot: hover, diagnostics,
;; document symbols); what was missing is the layout that follows you.
;;
;;   SPC t P   panels on/off:
;;     right, top     Output: what is at point (eldoc: type, signature,
;;                    docs; in Lean (nael-mode) the tactic state: hypotheses
;;                    and goals, as Isabelle's Output shows the proof state)
;;     right, bottom  Problems: this file's diagnostics (flycheck)
;;     left           Outline: the file's symbols (imenu, from the language
;;                    server where one runs), where you are highlighted;
;;                    RET or click goes there
;;
;; The panels follow the buffer you're in and update as you pause.
;;
;; Isabelle's Query panel (find theorems and constants by name across the
;; session) is SPC c j here: Doom's consult-eglot-symbols, the server's
;; workspace/symbol with live preview (checked with rust-analyzer: "dist"
;; finds geometry::distance across the crate).
;;
;;; Code:

(require 'cl-lib)
(require 'imenu)

(declare-function eldoc-doc-buffer "eldoc" (&optional interactive))
(declare-function flycheck-list-errors "ext:flycheck" ())

(defvar +pide--timer nil)
(defvar +pide--source nil "The buffer the panels show.")

(defun +pide--side (buffer side slot width-or-height)
  (display-buffer buffer
                  `(display-buffer-in-side-window
                    (side . ,side) (slot . ,slot)
                    ,(if (memq side '(left right))
                         `(window-width . ,width-or-height)
                       `(window-height . ,width-or-height))
                    (window-parameters . ((no-delete-other-windows . t)
                                          (no-other-window . t))))))

;;;; Outline

(defvar-local +pide--outline-source nil "The buffer this outline lists.")

(defun +pide--flatten (index &optional depth)
  "imenu INDEX as (DEPTH NAME . POSITION), depth first."
  (cl-loop for item in index
           when (and (consp item) (not (equal item imenu--rescan-item)))
           append (if (imenu--subalist-p item)
                      (cons (list (or depth 0) (car item) nil)
                            (+pide--flatten (cdr item) (1+ (or depth 0))))
                    (let ((pos (cdr item)))
                      (list (list (or depth 0) (car item)
                                  (if (overlayp pos) (overlay-start pos)
                                    (if (markerp pos) (marker-position pos) pos))))))))

(defvar +pide--index-cache nil "(BUFFER TICK . ENTRIES) of the last outline built.")

(defun +pide--entries (source)
  "SOURCE's outline entries, rebuilt only when its text changed (with a
language server, imenu asks it, and waits for the answer)."
  (let ((tick (buffer-chars-modified-tick source)))
    (if (and (eq (car +pide--index-cache) source) (eql (cadr +pide--index-cache) tick))
        (cddr +pide--index-cache)
      (let ((entries (with-current-buffer source
                       (ignore-errors
                         (let ((imenu-auto-rescan t))
                           (+pide--flatten (imenu--make-index-alist t)))))))
        (setq +pide--index-cache (cons source (cons tick entries)))
        entries))))

(defun +pide--outline-refresh (source)
  "Rewrite the outline for SOURCE; mark the entry point is in."
  (let* ((entries (+pide--entries source))
         (pt (with-current-buffer source (point)))
         (here (cl-loop for e in entries
                        when (and (nth 2 e) (<= (nth 2 e) pt)) maximize (nth 2 e))))
    (with-current-buffer (get-buffer-create "*pide outline*")
      (let ((inhibit-read-only t) (line nil))
        (erase-buffer)
        (setq +pide--outline-source source)
        (insert (propertize (buffer-name source) 'face 'bold) "\n")
        (dolist (e entries)
          (pcase-let ((`(,depth ,name ,pos) e))
            (when (and pos here (= pos here)) (setq line (line-number-at-pos)))
            (insert (make-string (* 2 depth) ?\s))
            (if pos
                (insert-text-button name
                                    'face (if (and here (eql pos here)) 'highlight 'default)
                                    'action (lambda (_) (pop-to-buffer source) (goto-char pos))
                                    'follow-link t)
              (insert (propertize name 'face 'font-lock-keyword-face)))
            (insert "\n")))
        (unless entries (insert (propertize "  (no symbols)\n" 'face 'shadow)))
        (special-mode)
        (when line
          (goto-char (point-min)) (forward-line (1- line))
          (when-let* ((w (get-buffer-window (current-buffer))))
            (set-window-point w (point))))))))

;;;; Following the cursor

(defun +pide--problems ()
  "flycheck's list for the selected buffer, as the panel under Output
(only here: elsewhere SPC c x shows it as before)."
  (when (and (bound-and-true-p flycheck-mode) (fboundp 'flycheck-list-errors))
    (let ((display-buffer-alist
           (cons '("\\`\\*Flycheck errors\\*\\'"
                   (display-buffer-in-side-window)
                   (side . right) (slot . 1) (window-height . 0.3))
                 display-buffer-alist)))
      (save-selected-window (flycheck-list-errors)))))

(defun +pide--panel-buffer-p (buf)
  (member (buffer-name buf) '("*pide outline*" "*Flycheck errors*" "*eldoc*")))

(defun +pide--update ()
  "Point the panels at the selected buffer and refresh the outline."
  (let ((buf (window-buffer (selected-window))))
    (unless (or (minibufferp buf) (+pide--panel-buffer-p buf)
                (string-prefix-p " " (buffer-name buf)))
      (unless (eq buf +pide--source)
        (setq +pide--source buf)
        (+pide--problems))
      (+pide--outline-refresh buf))))

;;;###autoload
(define-minor-mode +pide-mode
  "Isabelle/PIDE-style panels: Output, Problems, Outline (see the file)."
  :global t
  :group 'convenience
  (if +pide-mode
      (progn
        (setq +pide--source nil)
        (let ((source (current-buffer)))
          ;; eldoc's buffer exists once it has shown something.
          (when-let* ((doc (ignore-errors (eldoc-doc-buffer))))
            (+pide--side doc 'right 0 0.33))
          (+pide--problems)
          (+pide--outline-refresh source)
          (+pide--side "*pide outline*" 'left 0 0.2)
          (setq +pide--source source))
        (setq +pide--timer (run-with-idle-timer 0.5 t #'+pide--update)))
    (when +pide--timer (cancel-timer +pide--timer) (setq +pide--timer nil))
    (dolist (name '("*pide outline*" "*Flycheck errors*"))
      (when-let* ((w (get-buffer-window name))) (delete-window w)))
    (when-let* ((buf (ignore-errors (eldoc-doc-buffer)))
                (w (get-buffer-window buf)))
      (delete-window w))))

(map! :leader :desc "PIDE panels" "t P" #'+pide-mode)

(provide '+pide)
;;; +pide.el ends here
