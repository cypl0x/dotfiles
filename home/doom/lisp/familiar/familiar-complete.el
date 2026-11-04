;;; familiar-complete.el --- AI completions at point, explained -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.dev>
;; SPDX-License-Identifier: GPL-3.0-or-later
;;
;; This file is part of familiar (see familiar.el), not of GNU Emacs.
;;
;;; Commentary:
;;
;; `familiar-complete' (C-S-SPC in the author's config) asks the fast model
;; what could go at point: completions of the word being typed, or what
;; comes next (a line, a block), ranked by what fits the text around it.
;; They show in the completion popup (corfu, or *Completions*) in that
;; order, each with a line on why it fits, in the popup's documentation
;; window (corfu-popupinfo), like an IDE explains its suggestions.
;;
;; Nothing is sent until you ask; the answer is dropped if you typed or
;; moved meanwhile.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'familiar)

(declare-function corfu--exhibit "ext:corfu" ())

(defcustom familiar-complete-count 8
  "How many completions to ask for."
  :type 'natnum :group 'familiar)

(defcustom familiar-complete-excerpt 3000
  "Characters before point sent along (half as many after it)."
  :type 'natnum :group 'familiar)

(defconst familiar-complete--system
  "You complete text in an Emacs buffer at the cursor, marked ⟦here⟧ in the \
excerpt.  Offer what the writer most likely means to put there: the rest of \
the word being typed, or what comes next (a word, a line, a short block).  \
In code: valid for that language, using the names in the excerpt.  In \
prose: the same language and tone.  Reply with JSON only: {\"completions\": \
[{\"text\": \"the text, starting with the word being typed (given as \
`typed`) if any\", \"why\": \"one short line on why it fits\"}]}, best first."
  "System prompt of `familiar-complete'.")

(defun familiar-complete--bounds ()
  "Start and end of the word being typed at point (empty at a space)."
  (let ((beg (save-excursion (skip-syntax-backward "w_") (point))))
    (cons beg (point))))

(defun familiar-complete--request (beg)
  "What `familiar-complete' sends: an excerpt marked at point, the word
typed from BEG, the mode."
  (let ((from (max (point-min) (- (point) familiar-complete-excerpt)))
        (to (min (point-max) (+ (point) (/ familiar-complete-excerpt 2)))))
    (format "Buffer %s (%s).  typed: %S.  Up to %d completions.\n\n%s⟦here⟧%s"
            (buffer-name) major-mode (buffer-substring-no-properties beg (point))
            familiar-complete-count
            (buffer-substring-no-properties from (point))
            (buffer-substring-no-properties (point) to))))

(defun familiar-complete--candidates (answer typed)
  "ANSWER's completions that continue TYPED, best first, each with its
explanation as the text property `familiar-why'."
  (let ((case-fold-search t))
    (delete-dups
     (seq-keep (lambda (c)
                 (let ((text (plist-get c :text)))
                   (when (and (stringp text) (not (string-empty-p text))
                              (string-prefix-p typed text t))
                     (propertize text 'familiar-why (or (plist-get c :why) "")))))
               (plist-get answer :completions)))))

(defun familiar-complete--capf (beg end candidates)
  "A completion function offering CANDIDATES between BEG and END, as given."
  (lambda ()
    (list beg end
          (lambda (str pred action)
            (if (eq action 'metadata)
                '(metadata (display-sort-function . identity)
                           (cycle-sort-function . identity))
              (complete-with-action action candidates str pred)))
          :annotation-function
          (lambda (c) (when (string-search "\n" c) "  ⏎ more lines"))
          :company-doc-buffer
          (lambda (c)
            (let ((c (car (member c candidates))))
              (with-current-buffer (get-buffer-create " *familiar-complete*")
                (erase-buffer)
                (insert (or (get-text-property 0 'familiar-why c) "") "\n\n" c)
                (current-buffer))))
          :exclusive t)))

;; Opening the popup with the usual styles inserted the candidates' common
;; prefix ("with-current-buffer"), which matched the first one exactly, so
;; it was taken and the rest (a two-line block among them) were gone.  This
;; style shows them as given; typing on filters with your usual styles.
(defun familiar-complete--try (string _table _pred point)
  (cons string point))

(defun familiar-complete--all (_string table pred _point)
  (when-let* ((all (all-completions "" table pred)))
    (nconc all 0)))

(add-to-list 'completion-styles-alist
             '(familiar-as-given familiar-complete--try familiar-complete--all
               "Candidates as given: no prefix inserted, none filtered out."))

;;;###autoload
(defun familiar-complete ()
  "Completions at point from the fast model, ranked, each explained."
  (interactive)
  (pcase-let* ((buf (current-buffer))
               (`(,beg . ,end) (familiar-complete--bounds))
               (typed (buffer-substring-no-properties beg end))
               (tick (buffer-chars-modified-tick))
               (pt (point)))
    (message "✦ Completing…")
    (familiar-request
     (familiar-complete--request beg)
     :task 'complete :system familiar-complete--system :silent t
     :callback
     (lambda (response _info)
       (when (stringp response)
         (let* ((answer (ignore-errors
                          (json-parse-string
                           (replace-regexp-in-string "\\`[^{]*\\|[^}]*\\'" "" response)
                           :object-type 'plist :array-type 'list)))
                (cands (familiar-complete--candidates answer typed)))
           ;; From a timer: the popup wants the command loop, not a process
           ;; filter.  Not if you typed or moved meanwhile.
           (run-at-time
            0 nil
            (lambda ()
              (when (and (buffer-live-p buf) (eq (current-buffer) buf)
                         (= (point) pt) (= tick (buffer-chars-modified-tick)))
                (if (null cands)
                    (message "✦ No completion")
                  (message nil)
                  (let ((completion-at-point-functions
                         (list (familiar-complete--capf beg end cands)))
                        (completion-styles '(familiar-as-given))
                        (completion-category-overrides nil))
                    (completion-at-point)
                    ;; corfu draws from post-command-hook; there was no
                    ;; command (a timer), so draw now.
                    (when (and (bound-and-true-p completion-in-region-mode)
                               (fboundp 'corfu--exhibit))
                      (corfu--exhibit)))))))))))))

(provide 'familiar-complete)
;;; familiar-complete.el ends here
