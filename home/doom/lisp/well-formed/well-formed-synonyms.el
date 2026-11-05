;;; well-formed-synonyms.el --- Synonyms at point, offline (WordNet) -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Wolfhard Prell
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; M-x well-formed-synonyms (SPC P s): another word for the one at point,
;; from WordNet's `wn' (offline), ranked by the context:
;;
;;   - the part of speech the word plays here first (after "the" a noun,
;;     or an adjective when a word follows; after "to", a modal or a
;;     pronoun a verb; "-ly" an adverb), then the others;
;;   - within it WordNet's senses in its order (by estimated frequency),
;;     each sense's synonyms before its related words (=>);
;;   - words already used nearby last: a synonym is usually wanted to
;;     avoid a repetition.
;;
;; Each candidate shows its sense; the chosen one replaces the word in its
;; case (Bright → Brilliant).

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function well-formed--match-case "well-formed" (template replacement))

(defgroup well-formed-synonyms nil
  "Synonyms at point from WordNet."
  :group 'well-formed)

(defcustom well-formed-synonyms-program "wn"
  "WordNet's command line program."
  :type 'string)

(defcustom well-formed-synonyms-nearby 300
  "Characters around the word in which a used word ranks last."
  :type 'natnum)

(defconst well-formed-synonyms--pos
  '((noun . "-synsn") (verb . "-synsv") (adj . "-synsa") (adv . "-synsr"))
  "Parts of speech and the `wn' option for each one's synonyms.")

(defun well-formed-synonyms--clean (word)
  "WORD from `wn' output without its annotations: (vs. …), (predicate), #1."
  (string-trim (replace-regexp-in-string "([^)]*)\\|#[0-9]+" "" word)))

(defun well-formed-synonyms--parse (output)
  "Candidates in OUTPUT of `wn WORD -g -synsX'.
A list of (WORD GLOSS RELATED-P SENSE-NUMBER)."
  (let (out sense in-sense (n 0))
    (dolist (line (split-string output "\n"))
      (cond
       ((string-match-p "\\`Sense [0-9]+" line) (setq sense nil in-sense t n (1+ n)))
       ((or (not in-sense) (string-blank-p line) (string-match-p "Phrasal Verb\\|\\`\\s-*Also See" line)))
       (t
        (let* ((related (and (string-match-p "\\`\\s-*=> " line) t))
               (body (replace-regexp-in-string "\\`\\s-*\\(?:=> \\)?" "" line))
               (split (string-search " -- (" body))
               (words (if split (substring body 0 split) body))
               (gloss (and split (let ((g (substring body (+ split 5))))
                                   (string-trim (car (split-string g "[;)]")))))))
          (unless related (setq sense gloss))
          (dolist (w (split-string words "," t "[ \t]+"))
            (push (list (well-formed-synonyms--clean w) (or gloss sense) related n) out))))))
    (nreverse out)))

(defun well-formed-synonyms--lookup (word pos)
  "WORD's candidates as POS (a symbol in `well-formed-synonyms--pos')."
  (with-temp-buffer
    (call-process well-formed-synonyms-program nil t nil (downcase word) "-g"
                  (alist-get pos well-formed-synonyms--pos))
    (well-formed-synonyms--parse (buffer-string))))

(defun well-formed-synonyms--guess-pos (before word after)
  "Parts of speech for WORD between BEFORE (the word before, or nil) and
AFTER (the next word, or nil): the likely one first."
  (let* ((b (and before (downcase before)))
         (guess
          (cond ((string-suffix-p "ly" word) 'adv)
                ((member b '("to" "can" "could" "will" "would" "should" "must" "may" "might"
                             "i" "we" "they" "you" "he" "she" "it" "don't" "didn't" "doesn't"))
                 'verb)
                ((member b '("a" "an" "the" "this" "that" "these" "those" "my" "your" "his" "her"
                             "its" "our" "their" "some" "any" "every" "each" "no" "very" "so" "too"))
                 (if (and after (not (member b '("very" "so" "too")))) 'adj
                   (if (member b '("very" "so" "too")) 'adj 'noun)))
                ((member b '("is" "are" "was" "were" "be" "been" "seems" "looks" "feels")) 'adj))))
    (if guess
        (cons guess (remq guess (mapcar #'car well-formed-synonyms--pos)))
      (mapcar #'car well-formed-synonyms--pos))))

(defun well-formed-synonyms-candidates (word &optional before after nearby)
  "Ranked synonyms of WORD: list of (CANDIDATE POS SENSE).  BEFORE and
AFTER are the words around it; NEARBY the text around (its words rank last)."
  (let ((used (and nearby (split-string (downcase nearby) "[^[:alpha:]'-]+" t)))
        seen out)
    (cl-loop
     for pos in (well-formed-synonyms--guess-pos before word after)
     for pos-rank from 0 do
     (pcase-dolist (`(,w ,sense ,related ,n) (well-formed-synonyms--lookup word pos))
       (let ((key (downcase w)))
         (unless (or (equal key (downcase word)) (member key seen) (string-empty-p key))
           (push key seen)
           ;; Part of speech, then sense, its synonyms before its related
           ;; words, used ones last; `sort' is stable: WordNet's order within.
           (push (list w pos sense
                       (+ (* 100000 pos-rank) (* 2 n)
                          ;; => is a similar word for adjectives, a broader one
                          ;; (hypernym) for nouns and verbs: after all synonyms.
                          (cond ((not related) 0) ((eq pos 'adj) 1) (t 5000))
                          (if (member key used) 10000000 0)))
                 out)))))
    (mapcar (lambda (c) (list (nth 0 c) (nth 1 c) (nth 2 c)))
            (sort (nreverse out) (lambda (a b) (< (nth 3 a) (nth 3 b)))))))

;;;###autoload
(defun well-formed-synonyms ()
  "Replace the word at point with a synonym, ranked by the context."
  (interactive)
  (unless (executable-find well-formed-synonyms-program)
    (user-error "WordNet's `%s' isn't installed" well-formed-synonyms-program))
  (pcase-let* ((`(,beg . ,end) (or (bounds-of-thing-at-point 'word) (user-error "No word here")))
               (word (buffer-substring-no-properties beg end))
               (before (save-excursion (goto-char beg)
                                       (and (re-search-backward "\\<\\([[:alpha:]']+\\)[[:space:]]+\\=" (line-beginning-position 0) t)
                                            (match-string-no-properties 1))))
               (after (save-excursion (goto-char end)
                                      (and (looking-at "[[:space:]]+\\([[:alpha:]]+\\)")
                                           (match-string-no-properties 1))))
               (nearby (buffer-substring-no-properties (max (point-min) (- beg well-formed-synonyms-nearby))
                                                       (min (point-max) (+ end well-formed-synonyms-nearby))))
               (cands (or (well-formed-synonyms-candidates word before after nearby)
                          (user-error "WordNet knows no synonyms of %s" word)))
               (table (mapcar (lambda (c) (cons (car c) c)) cands))
               (choice (completing-read
                        (format "Instead of %s: " word)
                        (lambda (str pred action)
                          (if (eq action 'metadata)
                              `(metadata (display-sort-function . identity)
                                         (annotation-function
                                          . ,(lambda (c)
                                               (pcase-let ((`(,_ ,_ ,pos ,sense) (assoc c table)))
                                                 (concat (propertize (format "  %s" pos) 'face 'shadow)
                                                         (and sense (propertize (format "  %s" sense)
                                                                                'face 'completions-annotations)))))))
                            (complete-with-action action table str pred))))))
    (when (string-empty-p choice) (user-error "Nothing chosen"))
    (save-excursion
      (goto-char beg)
      (delete-region beg end)
      (insert (if (fboundp 'well-formed--match-case) (well-formed--match-case word choice) choice)))))

(provide 'well-formed-synonyms)
;;; well-formed-synonyms.el ends here
