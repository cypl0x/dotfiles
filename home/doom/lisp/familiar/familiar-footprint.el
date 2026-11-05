;;; familiar-footprint.el --- What the AI changed, kept apart from what you did -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; Every change the model makes in Emacs, recorded outside the buffers: by
;; its tools (replace_in_buffer, insert_at_prompt, set_minibuffer, and
;; whatever eval_elisp does) and by @inline / @replace.  Nothing is marked in
;; the text; your own edits are never recorded.
;;
;;   M-x familiar-footprint   the ledger, newest first
;;     RET   go there          =   the change, old and new
;;     r     take it back (only while its text is still as the model left it)
;;     g     refresh
;;
;; How: while familiar acts, `familiar-footprint--actor' names what acts,
;; and change hooks record each change made meanwhile; a streamed answer's
;; chunks join into one entry.  With no actor the hooks return at once.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'familiar)
(require 'familiar-ask)

(defcustom familiar-footprint-max 500
  "How many changes the ledger keeps."
  :type 'natnum :group 'familiar)

(defvar familiar-footprint--log nil
  "The changes, newest first: plists (:time :actor :buffer :beg :end :old :new).
:beg and :end are markers around the new text.")

(defvar-local familiar-footprint--before nil "(BEG . OLD-TEXT) of a change under way.")

(defun familiar-footprint--before-h (beg end)
  "While familiar acts, keep the text between BEG and END before it is changed."
  (when familiar-footprint--actor
    (setq familiar-footprint--before (cons beg (buffer-substring-no-properties beg end)))))

(defun familiar-footprint--after-h (beg end _len)
  "Log the change familiar just made between BEG and END.
A streamed answer's next chunk joins the entry before it."
  (when (and familiar-footprint--actor familiar-footprint--before)
    (let ((old (cdr familiar-footprint--before))
          (new (buffer-substring-no-properties beg end))
          (last (car familiar-footprint--log)))
      (setq familiar-footprint--before nil)
      (if (and last
               ;; A streamed answer: the next chunk right after the last.
               (equal (plist-get last :actor) familiar-footprint--actor)
               (eq (marker-buffer (plist-get last :end)) (current-buffer))
               ;; Its end marker moved past this insertion already.
               (= (plist-get last :end) end)
               (> end beg)
               (string-empty-p old))
          (plist-put last :new (concat (plist-get last :new) new))
        (push (list :time (current-time) :actor familiar-footprint--actor
                    :buffer (buffer-name)
                    :beg (copy-marker beg) :end (copy-marker end t)
                    :old old :new new)
              familiar-footprint--log)
        (when (> (length familiar-footprint--log) familiar-footprint-max)
          (setcdr (nthcdr (1- familiar-footprint-max) familiar-footprint--log) nil))))))

(add-hook 'before-change-functions #'familiar-footprint--before-h)
(add-hook 'after-change-functions #'familiar-footprint--after-h)

;; The tools act under their names.
(defvar familiar-footprint--wrapped nil "Tools already wrapped (names).")

(defun familiar-footprint-wrap-tools (tools)
  "Make each of TOOLS (gptel tools) record its edits under its name."
  (dolist (tool tools)
    (let ((name (gptel-tool-name tool))
          (fn (gptel-tool-function tool)))
      (unless (member name familiar-footprint--wrapped)
        (push name familiar-footprint--wrapped)
        (setf (gptel-tool-function tool)
              (lambda (&rest args)
                (let ((familiar-footprint--actor name))
                  (apply fn args))))))))

(familiar-footprint-wrap-tools familiar-ask-tools)

;;;; The ledger

(defun familiar-footprint--line (s)
  "S on one line, cut to 50 columns."
  (let ((s (replace-regexp-in-string "\n" "⏎" (string-trim s))))
    (truncate-string-to-width s 50 nil nil "…")))

(defun familiar-footprint--rows ()
  "The ledger's rows for `tabulated-list-entries'."
  (cl-loop for e in familiar-footprint--log for id from 0
           collect (list id
                         (vector (format-time-string "%F %R" (plist-get e :time))
                                 (plist-get e :actor)
                                 (let ((b (marker-buffer (plist-get e :beg))))
                                   (if b (buffer-name b) (concat (plist-get e :buffer) " (gone)")))
                                 (concat (if (string-empty-p (plist-get e :old)) ""
                                           (concat "−" (familiar-footprint--line (plist-get e :old)) " "))
                                         (if (string-empty-p (plist-get e :new)) ""
                                           (concat "+" (familiar-footprint--line (plist-get e :new)))))))))

(defun familiar-footprint--entry ()
  "The logged change on the ledger line at point."
  (or (nth (tabulated-list-get-id) familiar-footprint--log)
      (user-error "No change here")))

(defun familiar-footprint-visit ()
  "Go to the change at point."
  (interactive)
  (let* ((e (familiar-footprint--entry))
         (beg (plist-get e :beg)))
    (unless (marker-buffer beg) (user-error "Its buffer is gone"))
    (pop-to-buffer (marker-buffer beg))
    (goto-char beg)
    (pulse-momentary-highlight-region beg (plist-get e :end))))

(defun familiar-footprint-show ()
  "Show the change at point: what was there, what the model put."
  (interactive)
  (let ((e (familiar-footprint--entry)))
    (with-current-buffer (get-buffer-create "*familiar change*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s in %s, %s\n\n--- before\n%s\n\n+++ after\n%s\n"
                        (plist-get e :actor) (plist-get e :buffer)
                        (format-time-string "%F %T" (plist-get e :time))
                        (plist-get e :old) (plist-get e :new)))
        (goto-char (point-min))
        (special-mode))
      (display-buffer (current-buffer)))))

(defun familiar-footprint-revert ()
  "Take the change at point back, if its text is still what the model left."
  (interactive)
  (let* ((e (familiar-footprint--entry))
         (beg (plist-get e :beg)) (end (plist-get e :end)))
    (unless (marker-buffer beg) (user-error "Its buffer is gone"))
    (with-current-buffer (marker-buffer beg)
      (unless (equal (buffer-substring-no-properties beg end) (plist-get e :new))
        (user-error "Changed since: take it back by hand (RET goes there)"))
      (save-excursion
        (goto-char beg)
        (delete-region beg end)
        (insert (plist-get e :old))))
    (message "Taken back: %s in %s" (plist-get e :actor) (plist-get e :buffer))))

(defvar familiar-footprint-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'familiar-footprint-visit)
    (define-key map "=" #'familiar-footprint-show)
    (define-key map "r" #'familiar-footprint-revert)
    map))

(define-derived-mode familiar-footprint-mode tabulated-list-mode "Footprint"
  "The changes familiar's model made, newest first."
  (setq tabulated-list-format [("When" 16 t) ("By" 18 t) ("Buffer" 24 t) ("Change" 0 nil)])
  (setq tabulated-list-entries #'familiar-footprint--rows)
  (tabulated-list-init-header))

;;;###autoload
(defun familiar-footprint ()
  "List what the model changed in Emacs (tools, @inline), newest first."
  (interactive)
  (with-current-buffer (get-buffer-create "*familiar footprint*")
    (familiar-footprint-mode)
    (tabulated-list-print)
    (pop-to-buffer (current-buffer))))

(provide 'familiar-footprint)
;;; familiar-footprint.el ends here
