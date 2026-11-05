;;; well-formed-test.el --- Tests for well-formed -*- lexical-binding: t; -*-

(require 'ert)
(add-to-list 'load-path (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))
(require 'well-formed)
(require 'well-formed-report)
(require 'org)

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
(provide 'well-formed-test)
;;; well-formed-test.el ends here
