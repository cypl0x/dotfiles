;;; familiar-rate.el --- Rate prompts: as you type them, and your habits -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; Two ways to write better prompts:
;;
;;   live      pause while typing an M-ß prompt: a fast model scores it
;;             (★ to ★★★★★) with a tip of a few words, shown after the text.
;;             `familiar-rate-live' turns it off.
;;   review    M-x familiar-rate-prompts: the prompts you wrote (M-ß's
;;             history) are rated, and patterns you repeat get a better
;;             way to say them.
;;
;; Nothing the model says about your prompts is shown on its word: it
;; answers in JSON naming prompts by number, and what is shown are your
;; prompts as you wrote them, looked up by those numbers.  A finding that
;; names no prompt of yours, or a pattern seen in fewer than two, is
;; dropped (and counted, so you know).
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'familiar)
(require 'familiar-ask)

(defcustom familiar-rate-live t
  "Whether M-ß prompts are rated as you pause typing them."
  :type 'boolean :group 'familiar)

(defcustom familiar-rate-delay 1.5
  "Seconds of pause in the prompt before it is rated."
  :type 'number :group 'familiar)

(defcustom familiar-rate-min-length 12
  "Prompts shorter than this many characters aren't rated live."
  :type 'natnum :group 'familiar)

(defcustom familiar-rate-review-count 150
  "How many of your latest distinct prompts `familiar-rate-prompts' reviews."
  :type 'natnum :group 'familiar)

(defconst familiar-rate--about
  "The prompts are written in Emacs to an AI assistant (\"M-ß\").  Along \
with each, the assistant automatically gets the buffer it was asked from, \
its modes, point, the region or the text around point, and it can look \
around Emacs with tools: never suggest adding those.  Words like \
@follow-up, @inline, @model, @fast are directives, not text."
  "What raters are told about the prompts.")

(defconst familiar-rate--live-system
  (concat familiar-rate--about "  You rate one prompt before it is sent.  \
Reply with JSON only: {\"score\": 1-5, \"tip\": \"at most 12 words that would \
make it clearer or more specific; empty if it is fine\"}.  Judge what is \
written, don't guess intent beyond it.")
  "System prompt of the live rating.")

(defconst familiar-rate--review-system
  (concat familiar-rate--about "  You review the prompts one person wrote, \
numbered [N] (×K: written K times).  Reply with JSON only:
{\"summary\": \"two sentences on how they prompt\",
 \"patterns\": [{\"prompts\": [N, ...], \"title\": \"at most 8 words\",
               \"issue\": \"...\", \"suggestion\": \"...\",
               \"template\": \"a reusable better prompt, with {placeholders}\"}],
 \"ratings\": [{\"prompt\": N, \"score\": 1-5, \"why\": \"...\", \"better\": \"the prompt rewritten\"}]}
patterns: things they do repeatedly, each citing at least two prompt \
numbers from the list.  ratings: the 10 weakest prompts.  Cite only numbers \
from the list, and say only what those prompts show.")
  "System prompt of the review.")

(defun familiar-rate--json (text)
  "TEXT, a model's JSON answer (maybe fenced), parsed to a plist, or nil."
  (when (stringp text)
    (ignore-errors
      (json-parse-string (string-trim (replace-regexp-in-string "\\`[^{]*\\|[^}]*\\'" "" text))
                         :object-type 'plist :array-type 'list))))

(defun familiar-rate--prompt-text (text)
  "TEXT without its @directives (gptel's @presets too)."
  (let ((text (car (familiar-ask--keywords (car (familiar-ask--model-spec text))))))
    (dolist (preset (bound-and-true-p gptel--known-presets))
      (setq text (replace-regexp-in-string
                  (format "\\(?:^\\|[ \t]+\\)@%s\\b" (regexp-quote (symbol-name (car preset))))
                  "" text)))
    (string-trim text)))

;;;; Live

(defvar-local familiar-rate--timer nil)
(defvar-local familiar-rate--overlay nil)
(defvar-local familiar-rate--asked nil "Prompt text last sent for rating.")

(defun familiar-rate--stars (score)
  (let ((n (max 0 (min 5 (if (numberp score) (round score) 0)))))
    (concat (make-string n ?★) (make-string (- 5 n) ?☆))))

(defun familiar-rate--show (text)
  "Show TEXT after the prompt (nil: nothing)."
  (unless familiar-rate--overlay
    (setq familiar-rate--overlay (make-overlay (point-max) (point-max) nil t nil)))
  (move-overlay familiar-rate--overlay (point-max) (point-max))
  (overlay-put familiar-rate--overlay 'after-string
               (and text
                    ;; The cursor stays before it, at the end of the input.
                    (let ((s (concat "   " (propertize text 'face 'shadow))))
                      (put-text-property 0 1 'cursor t s)
                      s))))

(defun familiar-rate--changed (&rest _)
  "The prompt changed: clear the rating, rate again after a pause."
  (when (timerp familiar-rate--timer) (cancel-timer familiar-rate--timer))
  (familiar-rate--show nil)
  (setq familiar-rate--timer
        (run-with-idle-timer familiar-rate-delay nil #'familiar-rate--live (current-buffer))))

(defun familiar-rate--live (buf)
  "Rate the prompt in minibuffer BUF, if it is still being read."
  (when (and (buffer-live-p buf) (minibufferp buf)
             (eq buf (window-buffer (active-minibuffer-window))))
    (with-current-buffer buf
      (let ((text (string-trim (familiar-rate--prompt-text (minibuffer-contents-no-properties)))))
        (when (and (>= (length text) familiar-rate-min-length)
                   (not (equal text familiar-rate--asked)))
          (setq familiar-rate--asked text)
          (familiar-request
           text :task 'rate :system familiar-rate--live-system :silent t
           :callback
           (lambda (response _info)
             (when-let* ((answer (familiar-rate--json response))
                         ((buffer-live-p buf)))
               (with-current-buffer buf
                 ;; Only for the text rated: typing on made it stale.
                 (when (equal (string-trim (familiar-rate--prompt-text
                                            (minibuffer-contents-no-properties)))
                              text)
                   (familiar-rate--show
                    (string-trim (format "%s %s" (familiar-rate--stars (plist-get answer :score))
                                         (or (plist-get answer :tip) ""))))))))))))))

(defun familiar-rate--cleanup-h ()
  (when (timerp familiar-rate--timer) (cancel-timer familiar-rate--timer)))

(defun familiar-rate-setup-h ()
  "Rate the prompt being typed in this minibuffer (`familiar-rate-live')."
  (when familiar-rate-live
    (add-hook 'after-change-functions #'familiar-rate--changed nil t)
    (add-hook 'minibuffer-exit-hook #'familiar-rate--cleanup-h nil t)))

(add-hook 'familiar-ask-prompt-setup-hook #'familiar-rate-setup-h)

;;;; Review

(defun familiar-rate--collect ()
  "Your latest distinct prompts, directives out: list of (TEXT . COUNT)."
  (let ((counts (make-hash-table :test #'equal)) order)
    (dolist (p (bound-and-true-p familiar-ask-history))
      (let ((text (string-trim (familiar-rate--prompt-text p))))
        (unless (string-empty-p text)
          (unless (gethash text counts) (push text order))
          (cl-incf (gethash text counts 0)))))
    (mapcar (lambda (text) (cons text (gethash text counts)))
            (seq-take (nreverse order) familiar-rate-review-count))))

(defun familiar-rate--checked (answer prompts)
  "ANSWER's findings that hold up against PROMPTS: (PATTERNS RATINGS DROPPED).
A pattern needs two or more prompt numbers that exist, a rating one."
  (let ((valid (lambda (n) (and (integerp n) (<= 1 n (length prompts)))))
        (dropped 0) patterns ratings)
    (dolist (p (plist-get answer :patterns))
      (let ((ns (delete-dups (seq-filter valid (plist-get p :prompts)))))
        (if (< (length ns) 2) (cl-incf dropped)
          (push (plist-put (copy-sequence p) :prompts ns) patterns))))
    (dolist (r (plist-get answer :ratings))
      (if (funcall valid (plist-get r :prompt)) (push r ratings) (cl-incf dropped)))
    (list (nreverse patterns) (nreverse ratings) dropped)))

(defun familiar-rate--org-quote (text)
  "TEXT as an Org example line (no markup taken from it)."
  (concat ": " (replace-regexp-in-string "\n" "\n: " text)))

(defun familiar-rate--render (answer prompts)
  "Org text of the review ANSWER of PROMPTS ((TEXT . COUNT) ...)."
  (pcase-let ((`(,patterns ,ratings ,dropped) (familiar-rate--checked answer prompts))
              (cite (lambda (n)
                       (let ((p (nth (1- n) prompts)))
                         (concat (familiar-rate--org-quote (format "[%d] %s" n (car p)))
                                 (if (> (cdr p) 1) (format "   (×%d)" (cdr p)) ""))))))
    (concat
     (format "#+title: Your prompts, reviewed\n#+date: %s\n\n%d prompts reviewed%s.\n\n"
             (format-time-string "%F %R") (length prompts)
             (if (> dropped 0)
                 (format "; %d finding%s dropped: %s cited no prompt of yours (or one only, for a pattern)"
                         dropped (if (= dropped 1) "" "s") (if (= dropped 1) "it" "they"))
               ""))
     (when-let* ((summary (plist-get answer :summary))) (concat summary "\n\n"))
     "* Patterns\n"
     (if (null patterns) "None that held up.\n"
       (mapconcat
        (lambda (p)
          (concat "** " (or (plist-get p :title) "Pattern") "\n"
                  (when-let* ((issue (plist-get p :issue))) (concat issue "\n"))
                  (mapconcat (lambda (n) (concat (funcall cite n) "\n")) (plist-get p :prompts) "")
                  "\n" (or (plist-get p :suggestion) "") "\n"
                  (when-let* ((tpl (plist-get p :template)) ((not (string-empty-p tpl))))
                    (concat "\n#+begin_example\n" tpl "\n#+end_example\n"))))
        patterns ""))
     "\n* Weakest prompts\n"
     (if (null ratings) "None.\n"
       (mapconcat
        (lambda (r)
          (concat (format "** %s %s\n" (familiar-rate--stars (plist-get r :score))
                          (or (plist-get r :why) ""))
                  (funcall cite (plist-get r :prompt)) "\n"
                  (when-let* ((better (plist-get r :better)) ((not (string-empty-p better))))
                    (concat "\nBetter:\n" (familiar-rate--org-quote better) "\n"))))
        ratings "")))))

;;;###autoload
(defun familiar-rate-prompts ()
  "Review the prompts you wrote to M-ß: patterns you repeat, the weakest ones,
better ways to say them.  Shown in an Org buffer; what it quotes are your
prompts as written (see the Commentary of familiar-rate.el)."
  (interactive)
  (let ((prompts (familiar-rate--collect)))
    (when (< (length prompts) 3) (user-error "Too few prompts to review yet (%d)" (length prompts)))
    (message "familiar: reviewing %d prompts…" (length prompts))
    (familiar-request
     (cl-loop for (text . count) in prompts for i from 1
              concat (format "[%d]%s %s\n" i (if (> count 1) (format " (×%d)" count) "") text))
     :task 'review :system familiar-rate--review-system
     :callback
     (lambda (response _info)
       (if-let* ((answer (familiar-rate--json response)))
           (with-current-buffer (get-buffer-create "*familiar prompt review*")
             (let ((inhibit-read-only t))
               (erase-buffer)
               (insert (familiar-rate--render answer prompts))
               (org-mode)
               (goto-char (point-min)))
             (view-mode)
             (display-buffer (current-buffer)))
         (when response
           (message "familiar: the review came back unreadable")))))))

(provide 'familiar-rate)
;;; familiar-rate.el ends here
