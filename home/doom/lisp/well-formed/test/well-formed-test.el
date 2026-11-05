;;; well-formed-test.el --- Tests for well-formed -*- lexical-binding: t; -*-

(require 'ert)
(add-to-list 'load-path (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))
(require 'well-formed)
(require 'well-formed-report)
(require 'org)

;; Nothing written outside temp files (the report saves times at exit).
(setq well-formed-time-file (make-temp-file "wf-time" nil ".eld")
      well-formed-ignore-file (make-temp-file "wf-ignore" nil ".eld"))

(defmacro well-formed-test--with (mode text &rest body)
  (declare (indent 2))
  `(with-temp-buffer
     (let ((well-formed-ignore-file (make-temp-file "wf-ignore" nil ".eld"))
           (well-formed--ignored nil)
           (org-mode-hook nil) (text-mode-hook nil))
       (insert ,text)
       (funcall ,mode)
       ,@body)))

(defun well-formed-test--rules (mode text)
  "Rule ids found in TEXT under MODE, in order."
  (well-formed-test--with mode text
    (mapcar (lambda (f) (nth 2 f)) (well-formed-check))))

(defun well-formed-test--find (mode text rule)
  "The first finding of RULE in TEXT: (MATCHED-TEXT FIXES)."
  (well-formed-test--with mode text
    (when-let* ((f (cl-find rule (well-formed-check) :key (lambda (f) (nth 2 f)))))
      (list (nth 6 f) (nth 5 f)))))

;;;; Masking

(ert-deftest well-formed-test-org-masks-code-links-blocks ()
  (well-formed-test--with #'org-mode
      "* TODO Heading :tag:\nSee ~the the~ and =a apple= and [[https://x.y][a link]].\n#+begin_src elisp\n(the the)\n#+end_src\n| the the | a |\n"
    (let ((m (well-formed--masked-text (point-min) (point-max))))
      (should (string-match-p "\0+Heading \0+\n" m))
      (should-not (string-match-p "the the" m))
      (should-not (string-match-p "apple" m))
      (should (string-match-p "a link\0\0\\." m))
      (should-not (string-match-p "x\\.y" m))
      (should (= (length m) (buffer-size))))
    (should-not (cl-intersection '(repeated-word article) (mapcar (lambda (f) (nth 2 f)) (well-formed-check))))))

(ert-deftest well-formed-test-org-emphasis-kept-markers-masked ()
  (well-formed-test--with #'org-mode "Some *bold* and /italic/ words here.\n"
    (let ((m (well-formed--masked-text (point-min) (point-max))))
      (should (string-match-p "Some \0bold\0 and \0italic\0 words" m)))))

(ert-deftest well-formed-test-markdown-masks ()
  (well-formed-test--with #'text-mode "x"
    (ignore))
  (when (fboundp 'markdown-mode)
    (well-formed-test--with #'markdown-mode "# Title\n\nUse `the the` and [link](http://a.b).\n\n```\nthe the\n```\n"
      (should-not (memq 'repeated-word (mapcar (lambda (f) (nth 2 f)) (well-formed-check)))))))

(ert-deftest well-formed-test-prog-mode-comments-only ()
  (well-formed-test--with #'emacs-lisp-mode "(defun f () \"the the\" (a apple))\n;; This is the the comment.\n"
    (let ((ids (mapcar (lambda (f) (nth 2 f)) (well-formed-check))))
      (should (equal ids '(repeated-word))))))

;;;; Sentences and language

(ert-deftest well-formed-test-sentences ()
  (should (equal (length (well-formed--sentences "One. Two? Three! Four")) 4))
  (should (equal (length (well-formed--sentences "See e.g. this and Dr. Who. Next.")) 2))
  (should (equal (length (well-formed--sentences "Das ist z.B. gut. Ja.")) 2)))

(ert-deftest well-formed-test-language ()
  (should (equal (well-formed--detect-language "Das ist nicht die Lösung, und es wird auch nicht besser.") "de"))
  (should (equal (well-formed--detect-language "This is not the answer and it is not getting better.") "en"))
  (should-not (well-formed--detect-language "Hello")))

;;;; Correctness

(ert-deftest well-formed-test-repeated-word ()
  (should (equal (well-formed-test--find 'text-mode "We need the the result." 'repeated-word) '(" the" (""))))
  (should-not (memq 'repeated-word (well-formed-test--rules 'text-mode "He had had enough. That that is."))))

(ert-deftest well-formed-test-article ()
  (should (equal (well-formed-test--find 'text-mode "It is a apple." 'article) '("a" ("an"))))
  (should (equal (well-formed-test--find 'text-mode "It is an university." 'article) '("an" ("a"))))
  (should (equal (well-formed-test--find 'text-mode "It took a hour." 'article) '("a" ("an"))))
  (should (equal (well-formed-test--find 'text-mode "Run an SQL query." 'article) nil))
  (should (equal (well-formed-test--find 'text-mode "A user, an hour, a one-off, a URL." 'article) nil)))

(ert-deftest well-formed-test-spacing-and-punctuation ()
  (should (equal (well-formed-test--find 'text-mode "Hello , world." 'spacing) '(" " (""))))
  (should (equal (well-formed-test--find 'text-mode "One,two." 'spacing) '("," (", "))))
  (should (equal (car (well-formed-test--find 'text-mode "Really,, yes." 'punctuation)) ",,"))
  ;; Two spaces after a sentence (sentence-end-double-space) are fine.
  (should-not (memq 'spacing (well-formed-test--rules 'text-mode "It works.  It is fast."))))

(ert-deftest well-formed-test-capitalization ()
  (should (equal (well-formed-test--find 'text-mode "It works. it is fast." 'capitalization) '("it" ("It"))))
  (should (equal (well-formed-test--find 'text-mode "Then i left." 'capitalization) '("i" ("I"))))
  (should (equal (well-formed-test--find 'text-mode "We met on monday." 'capitalization) '("monday" ("Monday"))))
  (should-not (memq 'capitalization (well-formed-test--rules 'text-mode "It works. macOS is fine. npm too. git also."))))

(ert-deftest well-formed-test-confused-words ()
  (should (equal (well-formed-test--find 'text-mode "It was better then before." 'confused-word)
                 '("better then" ("better than"))))
  (should (equal (well-formed-test--find 'text-mode "Its a bug." 'confused-word) '("Its a" ("It's a"))))
  (should (equal (well-formed-test--find 'text-mode "You should of known." 'confused-word)
                 '("should of" ("should have"))))
  (should (equal (well-formed-test--find 'text-mode "Their is a way." 'confused-word) '("Their is" ("There is")))))

(ert-deftest well-formed-test-false-friends ()
  (should (equal (well-formed-test--find 'text-mode "I live here since three years." 'false-friend)
                 '("since three years" ("for three years"))))
  (should (equal (well-formed-test--find 'text-mode "Thanks for the informations." 'false-friend)
                 '("informations" ("information"))))
  (should (equal (well-formed-test--find 'text-mode "Can you explain me this?" 'false-friend)
                 '("explain me" ("explain to me")))))

(ert-deftest well-formed-test-known-term ()
  (should (equal (well-formed-test--find 'text-mode "I pushed it to Github." 'known-term) '("Github" ("GitHub"))))
  (should-not (memq 'known-term (well-formed-test--rules 'text-mode "The rust on the lean pipe."))))

(ert-deftest well-formed-test-german ()
  (should (equal (well-formed-test--find 'text-mode "Ich glaube, das er nicht kommt und es ist der Standart." 'dass)
                 '("das" ("dass"))))
  (should (equal (well-formed-test--find 'text-mode "Ich glaube, das er nicht kommt und es ist der Standart." 'misspelling-de)
                 '("Standart" ("Standard"))))
  (should-not (memq 'dass (well-formed-test--rules 'text-mode "Das ist das Auto, das ich nicht kaufe.")))
  (should (equal (well-formed-test--find 'text-mode "Wir sind seid gestern hier und es ist nicht schlimm." 'seit-seid)
                 '("seid" ("seit"))))
  (should (equal (well-formed-test--find 'text-mode "Das macht Sinn, und es ist auch nicht schlimm." 'misspelling-de)
                 '("macht Sinn" ("ergibt Sinn")))))

;;;; Clarity, engagement, delivery

(ert-deftest well-formed-test-wordy-redundant-complex ()
  (should (equal (well-formed-test--find 'text-mode "In order to win, we play." 'wordy) '("In order to" ("To"))))
  (should (equal (well-formed-test--find 'text-mode "The end result is good." 'redundant) '("end result" ("result"))))
  (should (equal (well-formed-test--find 'text-mode "We utilize tools." 'complex-word) '("utilize" ("use"))))
  (should (equal (well-formed-test--find 'text-mode "Wir müssen eine Entscheidung treffen, und das ist nicht leicht." 'wordy)
                 '("eine Entscheidung treffen" ("entscheiden")))))

(ert-deftest well-formed-test-long-sentence-by-style ()
  (let ((s (concat (mapconcat #'identity (make-list 35 "word") " ") ".")))
    (should (memq 'long-sentence (well-formed-test--rules 'text-mode s)))
    (should-not (memq 'long-sentence (well-formed-test--rules 'text-mode (concat "#+well_formed: academic\n\n" s))))
    (should-not (memq 'long-sentence (well-formed-test--rules 'text-mode (concat "well_formed: creative\n\n" s))))))

(ert-deftest well-formed-test-passive ()
  (should (memq 'passive (well-formed-test--rules 'text-mode "The file was deleted by the script.")))
  (should-not (memq 'passive (well-formed-test--rules 'text-mode "I was interested in it."))))

(ert-deftest well-formed-test-style-gates ()
  (should-not (memq 'contraction (well-formed-test--rules 'text-mode "We don't know.")))
  (should (memq 'contraction (well-formed-test--rules 'text-mode "#+well_formed: academic\n\nWe don't know.")))
  (should (memq 'informal (well-formed-test--rules 'text-mode "#+well_formed: business\n\nWe got lots of stuff."))))

(ert-deftest well-formed-test-overused-and-monotonous ()
  (should (memq 'overused (well-formed-test--rules
                           'text-mode
                           "The buffer holds text. Every buffer has a mode, and each buffer keeps its own state while the editor runs many things at once for you.")))
  (should (memq 'monotonous-start (well-formed-test--rules 'text-mode "We go. We stay. We leave."))))

;;;; Consistency

(ert-deftest well-formed-test-consistency ()
  (let ((found (well-formed-test--with #'text-mode
                   "The color is red. Another color is blue.\n\nThe colour is green. Send an email or an e-mail, or email.\n"
                 (well-formed-check))))
    (should (cl-find 'spelling-variety found :key (lambda (f) (nth 2 f))))
    (should (equal (nth 5 (cl-find 'spelling-variety found :key (lambda (f) (nth 2 f)))) '("color")))
    (should (equal (nth 6 (cl-find 'variant found :key (lambda (f) (nth 2 f)))) "e-mail"))))

;;;; Commands

(ert-deftest well-formed-test-fix-and-ignore ()
  (well-formed-test--with #'text-mode "We need the the result. It is a apple.\n"
    (goto-char (point-min))
    (search-forward "a apple")
    (backward-word 1) (backward-char 2)
    (well-formed-fix)
    (should (string-match-p "an apple" (buffer-string)))
    (goto-char (point-min))
    (search-forward "the the")
    (backward-char 2)
    (well-formed-fix)
    (should (string-match-p "need the result" (buffer-string)))
    ;; Ignore an occurrence (a non-file buffer keeps it locally).
    (erase-buffer)
    (insert "Use a apple.\n")
    (goto-char (+ (point-min) 4))
    (well-formed-ignore 'here)
    (should-not (memq 'article (mapcar (lambda (f) (nth 2 f)) (well-formed-check))))))

(ert-deftest well-formed-test-fix-refuses-stale ()
  (well-formed-test--with #'text-mode "It is a apple.\n"
    (let ((f (car (well-formed-check))))
      (goto-char (point-min)) (insert "X")
      (should-error (well-formed--apply (list (car f) (cadr f) (nth 2 f) nil nil nil "zz") "an")))))

(ert-deftest well-formed-test-cache-reuses-paragraphs ()
  (well-formed-test--with #'text-mode "First a apple.\n\nSecond paragraph is fine.\n"
    (well-formed-check)
    (let ((calls 0))
      (cl-letf* ((orig (symbol-function 'well-formed--check-para))
                 ((symbol-function 'well-formed--check-para)
                  (lambda (p) (cl-incf calls) (funcall orig p))))
        (goto-char (point-max)) (insert "\nThird one.\n")
        (well-formed-check)
        (should (= calls 1))))))

(ert-deftest well-formed-test-report ()
  (well-formed-test--with #'org-mode "#+title: T\n\nThis is a simple text. It has two sentences, and a apple.\n\nA second paragraph follows here.\n"
    (save-window-excursion (well-formed-report))
    (with-current-buffer "*well-formed report*"
      (should (string-match-p "Scores" (buffer-string)))
      (should (string-match-p "Flesch reading ease" (buffer-string)))
      (should (string-match-p "Tone" (buffer-string)))
      (kill-buffer))))

(ert-deftest well-formed-test-readability-numbers ()
  (let ((r (well-formed--readability '("The" "cat" "sat" "on" "the" "mat") 1 "en")))
    (should (> (alist-get 'ease r) 100))
    (should (< (alist-get 'fk-grade r) 1))))


(ert-deftest well-formed-test-agreement ()
  (should (equal (well-formed-test--find #'text-mode "Then he go home." 'agreement) '("go" ("goes"))))
  (should (equal (well-formed-test--find #'text-mode "They has a car." 'agreement) '("has" ("have"))))
  (should (equal (well-formed-test--find #'text-mode "It don't work." 'agreement) '("don't" ("doesn't"))))
  (should-not (memq 'agreement (well-formed-test--rules #'text-mode "Does he go home? Let it run fast. I hope that she have fun."))))

(ert-deftest well-formed-test-commas ()
  (should (equal (well-formed-test--find #'text-mode "However we left early." 'introductory-comma)
                 '("However" ("However,"))))
  (should-not (memq 'introductory-comma (well-formed-test--rules #'text-mode "However, we left early.")))
  (should (equal (well-formed-test--find #'text-mode "Ich weiß dass es nicht stimmt und das ist gut." 'comma-de)
                 '(" " (", "))))
  (should-not (memq 'comma-de (well-formed-test--rules #'text-mode "Ich gehe, sodass es nicht stimmt. Er kam, ohne dass es auffiel und das ist gut."))))

(ert-deftest well-formed-test-typography-vague-negative ()
  (should (equal (well-formed-test--find #'text-mode "This - and that." 'typography) '(" - " (" – "))))
  (should (equal (well-formed-test--find #'text-mode "We waited. This means we lost." 'vague-this) '("This means" nil)))
  (should (memq 'negative (well-formed-test--rules #'text-mode "#+well_formed: business\n\nDon't forget the report."))))

(defun well-formed-test--apply-first (mode text rule)
  "TEXT after applying RULE's first fix in MODE."
  (well-formed-test--with mode text
    (let ((f (cl-find rule (well-formed-check) :key (lambda (f) (nth 2 f)))))
      (should f)
      (should (nth 5 f))
      (well-formed--apply f (car (nth 5 f)))
      (buffer-string))))

(ert-deftest well-formed-test-fix-long-sentence-split ()
  (let ((s (concat "We built the parser for the new language over three long weeks in the spring, "
                   "and the team then tested every single part of it against the old suite of programs "
                   "that we had kept from the earlier project.")))
    (should (equal (well-formed-test--apply-first #'text-mode s 'long-sentence)
                   (concat "We built the parser for the new language over three long weeks in the spring. "
                           "The team then tested every single part of it against the old suite of programs "
                           "that we had kept from the earlier project.")))))

(ert-deftest well-formed-test-fix-passive-to-active ()
  (should (equal (well-formed-test--apply-first #'text-mode "The file was deleted by the script." 'passive)
                 "The script deleted the file."))
  (should (equal (well-formed-test--apply-first #'text-mode "Yesterday, the report was written by Anna and nobody read it." 'passive)
                 "Yesterday, Anna wrote the report and nobody read it."))
  ;; No actor: no rule-based fix (the AI rewrite can still do it).
  (well-formed-test--with #'text-mode "The file was deleted."
    (should-not (nth 5 (cl-find 'passive (well-formed-check) :key (lambda (f) (nth 2 f)))))))

(ert-deftest well-formed-test-fix-conjunction-adverb-oxford ()
  (should (equal (well-formed-test--apply-first #'text-mode "#+well_formed: academic\n\nIt rained. And we left." 'conjunction-start)
                 "#+well_formed: academic\n\nIt rained. We left."))
  (should (string-match-p "dropped to the" (well-formed-test--apply-first
                                            #'text-mode "It quickly, quietly and suddenly dropped to the floor." 'adverb)))
  (should (equal (well-formed-test--apply-first
                  #'text-mode "Red, green, and blue. Cats, dogs, and birds. Salt, pepper and oil." 'oxford-comma)
                 "Red, green, and blue. Cats, dogs, and birds. Salt, pepper, and oil.")))

(ert-deftest well-formed-test-every-finding-offers-ai-rewrite ()
  (let (called)
    (well-formed-test--with #'text-mode "We go. We stay. We leave."
      (let ((well-formed-rewrite-function (lambda (b e goal) (setq called (list b e goal))))
            (f (cl-find 'monotonous-start (well-formed-check) :key (lambda (f) (nth 2 f)))))
        (should-not (nth 5 f))
        (let ((fixes (well-formed--fixes f)))
          (should (= (length fixes) 1))
          (well-formed--apply f (car fixes)))
        (should (string-match-p "Third sentence" (nth 2 called)))
        (should (< (nth 0 called) (nth 1 called)))))))

(ert-deftest well-formed-test-ai-layer ()
  (require 'well-formed-ai)
  (clrhash well-formed-ai--cache)
  (setq well-formed-ai--sent nil)
  (let ((requests nil) (callback nil))
    (cl-letf (((symbol-function 'familiar-request)
               (lambda (prompt &rest args) (push prompt requests) (setq callback (plist-get args :callback)))))
      (well-formed-test--with #'org-mode "#+well_formed_goal: a friendly note for Emacs users\n\nAn old paragraph that was here before, with enough words in it.\n\nShort.\n"
        (well-formed-mode 1)
        (well-formed-ai-mode 1)
        (unwind-protect
            (progn
              ;; What was there when the buffer was first checked isn't sent.
              (well-formed-check)
              (should (null requests))
              (goto-char (point-max))
              (insert "\nThe configuration of the system was done in a way that it is working now fine for me.\n")
              (well-formed-check)
              ;; One request: the long paragraph, with the goal; not the short one.
              (should (= (length requests) 1))
              (should (string-match-p "friendly note for Emacs users" (car requests)))
              ;; Asked once: a second check while pending sends nothing new.
              (well-formed-check)
              (should (= (length requests) 1))
              ;; The answer: a finding with its rewrite, located by its quote.
              (funcall callback "{\"issues\": [{\"quote\": \"was done in a way that it is working now fine\", \"issue\": \"Wordy and the word order is off\", \"category\": \"clarity\", \"severity\": \"warning\", \"fix\": \"now works fine\"}]}" nil)
              (let* ((found (well-formed-check))
                     (f (cl-find 'ai found :key (lambda (f) (nth 2 f)))))
                (should f)
                (should (equal (nth 6 f) "was done in a way that it is working now fine"))
                (should (equal (nth 5 f) '("now works fine")))
                (should (memq f well-formed--findings))
                ;; Fixing it rewrites the quote.
                (well-formed--apply f (car (nth 5 f)))
                (should (string-match-p "system now works fine for me" (buffer-string)))))
          (well-formed-ai-mode -1))))))
(provide 'well-formed-test)
;;; well-formed-test.el ends here

(ert-deftest well-formed/interrupted-check-keeps-the-last-highlights ()
  "An abandoned check answers with the last result (moved with the text),
never `interrupted', which would make flycheck clear every highlight."
  (with-temp-buffer
    (insert "One very long sentence here.")
    (well-formed--remember (list (list 5 9 'weasel 'warning "very")))
    (goto-char (point-min)) (insert "XX ")
    (should (equal (well-formed--remembered) (list (list 8 12 'weasel 'warning "very"))))
    (let (reported)
      (cl-letf (((symbol-function 'well-formed--check-quietly) (lambda () :interrupted))
                ((symbol-function 'well-formed--recheck-later) #'ignore)
                ((symbol-function 'flycheck-error-new) (lambda (&rest args) args)))
        (well-formed--flycheck-start 'well-formed (lambda (status &optional data) (setq reported (list status data)))))
      (should (eq (car reported) 'finished))
      (should (equal (plist-get (car (cadr reported)) :column) 8)))))

;;;; New rules: comma splices, plurals, numbers, terms, dates, headings

(defun well-formed-test--ids (mode text)
  (well-formed-test--with mode text (mapcar (lambda (f) (nth 2 f)) (well-formed-check))))

(ert-deftest well-formed-test-comma-splice ()
  (should (equal (well-formed-test--apply-first #'text-mode "The build passed, it is ready." 'comma-splice)
                 "The build passed; it is ready."))
  (well-formed-test--with #'text-mode "The build passed, it is ready."
    (let ((f (cl-find 'comma-splice (well-formed-check) :key (lambda (f) (nth 2 f)))))
      (well-formed--apply f (cadr (nth 5 f)))
      (should (equal (buffer-string) "The build passed. It is ready."))))
  ;; An opening clause, a list, and "that is" are no splices.
  (dolist (ok '("If the build passed, it is ready."
                "When we left the house, it was raining."
                "Red, green, it is all fine."
                "We tested it, that is all."))
    (should-not (memq 'comma-splice (well-formed-test--ids #'text-mode ok)))))

(ert-deftest well-formed-test-apostrophe-plural ()
  (should (equal (well-formed-test--apply-first #'text-mode "Music of the 1990's was loud." 'apostrophe-plural)
                 "Music of the 1990s was loud."))
  (should (equal (well-formed-test--apply-first #'text-mode "We bought two CD's today." 'apostrophe-plural)
                 "We bought two CDs today."))
  (should (equal (well-formed-test--apply-first #'text-mode "The API's are slow today." 'apostrophe-plural)
                 "The APIs are slow today."))
  (dolist (ok '("NASA's mission went well." "Page 12's footer is odd."))
    (should-not (memq 'apostrophe-plural (well-formed-test--ids #'text-mode ok)))))

(ert-deftest well-formed-test-number-style ()
  (let ((text "We have three cats.\n\nThey ate four mice.\n\nThen 5 birds came.\n\nIt took 3 min.\n"))
    (should (equal (well-formed-test--apply-first #'text-mode text 'number-style)
                   "We have three cats.\n\nThey ate four mice.\n\nThen five birds came.\n\nIt took 3 min.\n"))
    ;; Units don't count, and only one minority finding.
    (should (= (cl-count 'number-style (well-formed-test--ids #'text-mode text)) 1))))

(ert-deftest well-formed-test-term-case ()
  (let ((text "We host on GitHub.\n\nGitHub is fine.\n\nAsk Github or github.com for help.\n"))
    (should (equal (well-formed-test--apply-first #'text-mode text 'term-case)
                   "We host on GitHub.\n\nGitHub is fine.\n\nAsk GitHub or github.com for help.\n"))
    ;; A domain is not the term.
    (should (= (cl-count 'term-case (well-formed-test--ids #'text-mode text)) 1))))

(ert-deftest well-formed-test-date-format ()
  (let ((text "It began on 2026-11-05.\n\nIt ended on 2026-12-01.\n\nWe met on 24.12.2026 again.\n"))
    (should (equal (well-formed-test--apply-first #'text-mode text 'date-format)
                   "It began on 2026-11-05.\n\nIt ended on 2026-12-01.\n\nWe met on 2026-12-24 again.\n")))
  ;; Not a date: 31.02.2026.
  (should-not (memq 'date-format (well-formed-test--ids #'text-mode "On 2026-01-01 and 2026-01-02.\n\nOr 31.02.2026.\n"))))

(ert-deftest well-formed-test-heading-case ()
  (let ((text "* Setting up the new machine\n\nText here.\n\n* Moving all the files over\n\nMore text.\n\n* Cleaning Up The Old Disk\n\nDone.\n"))
    (should (equal (well-formed-test--apply-first #'org-mode text 'heading-case)
                   "* Setting up the new machine\n\nText here.\n\n* Moving all the files over\n\nMore text.\n\n* Cleaning up the old disk\n\nDone.\n"))))

(ert-deftest well-formed-test-consistency-spares-names-and-counts ()
  "Paths, handles, package names and a lower-case majority (a hostname)
aren't the term; digits beside other numbers stay digits."
  (let ((ids (well-formed-test--ids
              #'text-mode
              "We use GitHub daily.\n\nOpen /github/owner and ask @github.\n\nThe thinkpad and the thinkpad again, on a ThinkPad.\n\nWe have three cats.\n\nThey ate four mice.\n\nWe did 6 of 8 steps.\n")))
    (should-not (memq 'term-case ids))
    (should-not (memq 'number-style ids))))

(ert-deftest well-formed-test-mode-line-score-and-words-today ()
  "After a check the mode line has the score; words count from the day's
first check; a goal shows the way there."
  (let ((well-formed--day-start (make-hash-table :test #'equal))
        (well-formed-daily-goal nil))
    (well-formed-test--with #'text-mode "The cat sat on the mat. It was warm.\n"
      (well-formed-mode 1)
      (well-formed-check)
      (should (string-match "\\`✎\\([0-9]+\\)\\'" well-formed--mode-line))
      (should (<= 0 (string-to-number (match-string 1 well-formed--mode-line)) 100))
      (goto-char (point-max))
      (insert "Then the dog came in and lay down too.\n")
      (well-formed-check)
      (should (string-suffix-p " +9" well-formed--mode-line))
      (let ((well-formed-daily-goal 5))
        (well-formed-check)
        (should (string-suffix-p " +9 ✓" well-formed--mode-line)))
      (should (string-match-p "Writing score" (get-text-property 0 'help-echo well-formed--mode-line)))
      ;; (format-mode-line is "" without a frame: the entry is checked live.)
      (should (member well-formed--mode-line-entry mode-line-misc-info)))))
