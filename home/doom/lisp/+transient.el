;;; lisp/+transient.el --- Reopen the last transient menu -*- lexical-binding: t; -*-
;;
;; SPC ' reopened the last minibuffer; now it reopens whatever closed last,
;; a minibuffer or a transient menu (magit's, casual's, the Tailscale or
;; well-formed menu …).  C-u SPC ' picks from the menus used lately, newest
;; first, with where each was opened.  Inside a reopened menu, C-M-p brings
;; back the arguments it had (transient's own history).
;;
;;; Code:

(require 'cl-lib)
(require 'eieio)

(defvar transient--prefix)
(defvar +minibuffer--ring)
(defvar +minibuffer--closed-at)
(declare-function transient-setup "ext:transient" (&optional name layout edit &rest params))
(declare-function +minibuffer/resume "+completion" ())

(defvar +transient-ring-size 20
  "How many transient menus `+transient/resume' remembers.")

(defvar +transient--ring nil
  "Transient menus opened, newest first: plists (:prefix :scope :buffer :time).")

(defvar +transient--resuming nil)

(defun +transient--record-a (&optional name _layout _edit &rest _params)
  "After `transient-setup' opened prefix NAME: remember it."
  (when (and name (symbolp name) (bound-and-true-p transient--prefix))
    (let ((entry (list :prefix name
                       :scope (ignore-errors (funcall #'eieio-oref transient--prefix (intern "scope")))
                       :buffer (buffer-name)
                       :time (float-time))))
      (setq +transient--ring
            (seq-take (cons entry (cl-remove name +transient--ring
                                             :key (lambda (e) (plist-get e :prefix))))
                      +transient-ring-size)))))

(with-eval-after-load 'transient
  (advice-add 'transient-setup :after #'+transient--record-a))

(defun +transient--open (entry)
  (let ((prefix (plist-get entry :prefix))
        (scope (plist-get entry :scope)))
    (if scope
        ;; Opened for something (a branch, a peer): open it for that again.
        (transient-setup prefix nil nil :scope scope)
      (call-interactively prefix))))

;;;###autoload
(defun +transient/resume (&optional choose)
  "Reopen the last transient menu; with CHOOSE (\\[universal-argument]),
pick one of the recent ones."
  (interactive "P")
  (unless +transient--ring (user-error "No transient menu to reopen yet"))
  (+transient--open
   (if (not choose)
       (car +transient--ring)
     (let* ((choices (mapcar (lambda (e)
                               (cons (format "%-32s %s, %s ago"
                                             (plist-get e :prefix) (plist-get e :buffer)
                                             (let ((s (- (float-time) (plist-get e :time))))
                                               (cond ((< s 60) (format "%ds" s))
                                                     ((< s 3600) (format "%dmin" (/ s 60)))
                                                     (t (format "%dh" (/ s 3600))))))
                                     e))
                             +transient--ring)))
       (cdr (assoc (completing-read "Reopen menu: " choices nil t) choices))))))

;;;###autoload
(defun +resume/last (&optional choose)
  "Reopen what closed last: a minibuffer (`+minibuffer/resume') or a
transient menu (`+transient/resume').  With CHOOSE (\\[universal-argument]),
pick one of the recent menus."
  (interactive "P")
  (let ((menu (plist-get (car +transient--ring) :time))
        (mini (and (bound-and-true-p +minibuffer--ring) (bound-and-true-p +minibuffer--closed-at))))
    (cond (choose (+transient/resume t))
          ((and menu (or (not mini) (> menu mini))) (+transient/resume))
          (t (+minibuffer/resume)))))

(map! :leader :desc "Reopen last minibuffer or menu" "'" #'+resume/last)

(provide '+transient)
;;; +transient.el ends here
