;;; lisp/+vocab.el --- leo lookups become flashcards (org-fc) -*- lexical-binding: t; -*-
;;
;; Every word you look up with leo (SPC l w) lands in ~/vault/vocabulary.org
;; as an org-fc "double" card: the word on the front, leo's best matches on
;; the back, quizzed in both directions.  Looking a word up again bumps its
;; LEO_LOOKUPS count, so the words you keep forgetting stand out.
;;
;;   SPC l r   review the due cards (org-fc; RET/n flip, then rate)
;;   SPC l v   open the vocabulary file
;;
;;; Code:

(declare-function org-fc-type-double-init "org-fc-type-double" ())
(declare-function org-fc-review-buffer "org-fc-review" ())
(declare-function org-find-exact-headline-in-buffer "org" (heading &optional buffer pos-only))
(declare-function org-entry-get "org" (epom property &optional inherit literal-nil))
(declare-function org-entry-put "org" (epom property value))
(defvar org-fc-directories)
(defvar org-fc-default-algo)

(defvar +vocab-file (expand-file-name "~/vault/vocabulary.org")
  "Where looked-up words are collected as flashcards.")

(defvar +vocab-max-translations 6
  "Most leo matches kept on a card's back.")

(defun +vocab--clean (s)
  (string-trim (replace-regexp-in-string "[ \t\n]+" " " (or s ""))))

(defun +vocab-translations (results)
  "The first `+vocab-max-translations' pairs of leo RESULTS, as strings.
RESULTS are what `leo--open-translation-buffer' gets: sections of
entries, each entry two sides with a `result' string."
  (let (out)
    (catch 'full
      (dolist (section results)
        (let ((pos (caar section)))
          (dolist (entry (cdar section))
            (push (format "%s — %s  /%s/"
                          (+vocab--clean (cdr (assoc 'result (car entry))))
                          (+vocab--clean (cdr (assoc 'result (cadr entry))))
                          pos)
                  out)
            (when (>= (length out) +vocab-max-translations)
              (throw 'full nil))))))
    (nreverse out)))

(defun +vocab-record (word lang translations)
  "Add WORD (looked up between LANG and German) with TRANSLATIONS as a card.
A word already there only gets its lookup count and date updated."
  (with-current-buffer (find-file-noselect +vocab-file)
    (unless (derived-mode-p 'org-mode) (org-mode))
    (save-excursion
      (save-restriction
        (widen)
        (let ((now (format-time-string "[%F %a %R]")))
          (if-let* ((pos (org-find-exact-headline-in-buffer word nil t)))
              (progn
                (goto-char pos)
                (org-entry-put nil "LEO_LOOKUPS"
                               (number-to-string
                                (1+ (string-to-number (or (org-entry-get nil "LEO_LOOKUPS") "0")))))
                (org-entry-put nil "LEO_LAST" now))
            (goto-char (point-max))
            (unless (bolp) (insert "\n"))
            (when (= (point) (point-min))
              (insert "#+title: Vocabulary (from leo lookups)\n\n"))
            (let ((heading (point)))
              (insert "* " word "\n** Back\n"
                      (mapconcat (lambda (tr) (concat "- " tr)) translations "\n")
                      "\n")
              (goto-char heading)
              (org-entry-put nil "LEO_LANG" lang)
              (org-entry-put nil "LEO_LOOKUPS" "1")
              (org-entry-put nil "LEO_LAST" now)
              (when (require 'org-fc nil t)
                (let ((org-fc-default-algo 'sm2))
                  (org-fc-type-double-init))))))))
    (let ((save-silently t)) (save-buffer))))

(defun +vocab--record-a (results _forums word lang _similar)
  "After leo shows RESULTS for WORD, keep it as a flashcard."
  (when results
    (condition-case err
        (+vocab-record (+vocab--clean word) lang (+vocab-translations results))
      (error (message "vocab: couldn't record %s: %s" word (error-message-string err))))))

(with-eval-after-load 'leo
  (advice-add 'leo--open-translation-buffer :after #'+vocab--record-a))

;; org-fc (fce1cb2, upstream HEAD on 2026-11-06) builds every card's
;; algorithm as (funcall CONSTRUCTOR ()): that nil is EIEIO's obsolete
;; object-name argument, so each card read said "Obsolete name argument
;; nil passed to org-fc-algo-sm2 constructor" in the echo area.
(defun +vocab--algo-constructor-a (ctor)
  "CTOR, minus the obsolete leading nil org-fc passes it."
  (lambda (&rest slots) (apply ctor (if (equal slots '(nil)) nil slots))))

(with-eval-after-load 'org-fc
  (add-to-list 'org-fc-directories (file-name-directory +vocab-file))
  (setq org-fc-default-algo 'sm2)
  (advice-add 'org-fc-algo-constructor :filter-return #'+vocab--algo-constructor-a))

(defun +vocab/review ()
  "Review the due vocabulary cards."
  (interactive)
  (require 'org-fc)
  (with-current-buffer (find-file-noselect +vocab-file)
    (org-fc-review-buffer)))

(defun +vocab/open ()
  "Open the vocabulary file."
  (interactive)
  (find-file +vocab-file))

(map! :leader
      (:prefix "l"
       :desc "Review vocabulary"    "r" #'+vocab/review
       :desc "Vocabulary file"      "v" #'+vocab/open))

(provide '+vocab)
;;; +vocab.el ends here
