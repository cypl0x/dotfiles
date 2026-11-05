;;; well-formed-report.el --- Scores, readability, tone and statistics of a text -*- lexical-binding: t; -*-
;;
;;; Commentary:
;;
;; M-x well-formed-report: one page about the buffer (or region):
;;   - scores: overall and per category, from the findings per 100 words
;;   - counts and times: words, sentences, reading and speaking time, and
;;     the time you spent writing it (tracked while well-formed-mode is on)
;;   - readability: Flesch reading ease (Amstad for German), Flesch–Kincaid
;;     grade, Gunning fog, SMOG, Coleman–Liau, ARI, LIX and, for German,
;;     the Wiener Sachtextformel
;;   - tone: how the text leans (academic, technical, business,
;;     conversational, storytelling, persuasive) in percent, plus formality,
;;     confidence and sentiment scales, all from word statistics
;;   - plots: sentence lengths through the text, their histogram, reading
;;     ease per paragraph
;;   - the findings by rule, and the words used most
;; Everything is a button: a sentence, a paragraph, a rule.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'well-formed)

(declare-function jinx--force-overlays "ext:jinx" (start end &optional visible))

(defvar-local well-formed--report-source nil "The buffer, start and end the report is about.")

(defface well-formed-report-heading '((t :inherit font-lock-keyword-face :weight bold))
  "Section headings in the report." :group (quote well-formed))
(defface well-formed-report-bar '((t :inherit success))
  "Bars in the report." :group (quote well-formed))

;;;; Writing time

(defcustom well-formed-time-file
  (expand-file-name "well-formed-time.eld" (file-name-directory well-formed-ignore-file))
  "Where the time spent writing each file is kept."
  :type 'file :group 'well-formed)

(defvar well-formed--times nil "Hash: file → seconds spent editing it.")
(defvar-local well-formed--last-edit nil)
(defvar-local well-formed--last-tick nil)

(defun well-formed--times ()
  (or well-formed--times
      (setq well-formed--times
            (let ((h (make-hash-table :test #'equal)))
              (when (file-readable-p well-formed-time-file)
                (ignore-errors
                  (with-temp-buffer
                    (insert-file-contents well-formed-time-file)
                    (pcase-dolist (`(,f . ,s) (read (current-buffer))) (puthash f s h)))))
              h))))

(defun well-formed--save-times ()
  (when well-formed--times
    (make-directory (file-name-directory well-formed-time-file) t)
    (let (alist)
      (maphash (lambda (k v) (push (cons k v) alist)) well-formed--times)
      (with-temp-file well-formed-time-file (prin1 alist (current-buffer))))))

(defun well-formed--track-time ()
  "After a command: count the time since the last edit as writing, up to
two minutes (longer pauses aren't writing)."
  (let ((tick (buffer-chars-modified-tick)))
    (unless (eql tick well-formed--last-tick)
      (let ((now (float-time)))
        (when (and well-formed--last-edit (or buffer-file-name (buffer-name)))
          (cl-incf (gethash (or buffer-file-name (buffer-name)) (well-formed--times) 0)
                   (min 120 (- now well-formed--last-edit))))
        (setq well-formed--last-edit now well-formed--last-tick tick)))))

(defun well-formed--time-setup ()
  (if well-formed-mode
      (add-hook 'post-command-hook #'well-formed--track-time nil t)
    (remove-hook 'post-command-hook #'well-formed--track-time t)))

(add-hook 'well-formed-mode-hook #'well-formed--time-setup)
(add-hook 'kill-emacs-hook #'well-formed--save-times)
(defvar well-formed--save-timer (run-with-idle-timer 300 t #'well-formed--save-times))

;;;; Statistics

(defun well-formed--duration (seconds)
  (cond ((< seconds 60) (format "%d s" (round seconds)))
        ((< seconds 3600) (format "%d min" (round (/ seconds 60))))
        (t (format "%d h %d min" (floor (/ seconds 3600)) (round (/ (mod seconds 3600) 60))))))

(defun well-formed--complex-p (word lang)
  "Three or more syllables (en), or a long word (de: over 6 letters for LIX)."
  (if (equal lang "de") (> (length word) 6) (>= (well-formed--syllables word) 3)))

(defun well-formed--readability (words sentences lang)
  "Readability indices for WORDS (strings) in SENTENCES (count): alist."
  (let* ((n (max 1 (length words)))
         (s (max 1 sentences))
         (syll (apply #'+ (mapcar #'well-formed--syllables words)))
         (letters (apply #'+ (mapcar #'length words)))
         (poly (cl-count-if (lambda (w) (>= (well-formed--syllables w) 3)) words))
         (long (cl-count-if (lambda (w) (> (length w) 6)) words))
         (asl (/ (float n) s)) (asw (/ (float syll) n)))
    `((ease . ,(if (equal lang "de") (- 180 asl (* 58.5 asw)) (- 206.835 (* 1.015 asl) (* 84.6 asw))))
      (fk-grade . ,(- (+ (* 0.39 asl) (* 11.8 asw)) 15.59))
      (fog . ,(* 0.4 (+ asl (* 100 (/ (float poly) n)))))
      (smog . ,(+ 3.1291 (* 1.043 (sqrt (* poly (/ 30.0 s))))))
      (coleman-liau . ,(- (+ (* 0.0588 (* 100 (/ (float letters) n))) (* -0.296 (* 100 (/ (float s) n)))) 15.8))
      (ari . ,(- (+ (* 4.71 (/ (float letters) n)) (* 0.5 asl)) 21.43))
      (lix . ,(+ asl (* 100 (/ (float long) n))))
      (wstf . ,(- (+ (* 0.1935 (* 100 (/ (float poly) n))) (* 0.1672 asl)
                     (* 0.1297 (* 100 (/ (float long) n))))
                  (* 0.0327 (* 100 (/ (float (cl-count-if (lambda (w) (= (well-formed--syllables w) 1)) words)) n)))
                  0.875)))))

(defun well-formed--ease-band (score)
  (cond ((>= score 90) "very easy") ((>= score 80) "easy") ((>= score 70) "fairly easy")
        ((>= score 60) "plain") ((>= score 50) "fairly difficult") ((>= score 30) "difficult")
        (t "very difficult")))

;;;; Tone

(defconst well-formed--tone-lexicon
  '((academic
     "however" "therefore" "thus" "moreover" "furthermore" "whereas" "hypothesis" "analysis" "evidence"
     "significant" "suggest" "suggests" "indicate" "indicates" "consequently" "hence" "theory" "method"
     "study" "results" "conclude" "data" "framework" "approach" "respectively" "namely" "albeit"
     "jedoch" "daher" "somit" "folglich" "zudem" "ferner" "Hypothese" "Analyse" "Ergebnisse" "Studie"
     "Methode" "Theorie" "signifikant" "deutet" "belegt" "beziehungsweise" "hinsichtlich")
    (technical
     "function" "server" "config" "configuration" "install" "error" "file" "files" "data" "system"
     "version" "command" "build" "package" "module" "buffer" "process" "memory" "cache" "query" "api"
     "kernel" "compile" "binary" "default" "option" "variable" "implementation" "interface" "protocol"
     "Funktion" "Datei" "Dateien" "Fehler" "Befehl" "Paket" "Modul" "Speicher" "Schnittstelle" "Konfiguration")
    (business
     "customer" "customers" "client" "clients" "team" "market" "revenue" "goal" "goals" "strategy"
     "stakeholder" "stakeholders" "budget" "deadline" "meeting" "project" "growth" "sales" "roi" "kpi"
     "Kunde" "Kunden" "Markt" "Umsatz" "Ziel" "Ziele" "Strategie" "Budget" "Projekt" "Termin" "Wachstum")
    (conversational
     "you" "yeah" "hey" "okay" "ok" "well" "pretty" "really" "actually" "anyway" "stuff" "guess" "lol"
     "du" "dich" "dir" "halt" "eben" "mal" "ja" "naja" "okay" "echt" "krass" "genau")
    (storytelling
     "suddenly" "then" "once" "said" "asked" "replied" "whispered" "walked" "looked" "felt" "remembered"
     "night" "morning" "she" "he" "her" "his" "himself" "herself" "began" "finally"
     "plötzlich" "dann" "einmal" "sagte" "fragte" "antwortete" "ging" "sah" "fühlte" "Nacht" "Morgen"
     "sie" "er" "ihr" "sein" "seine" "schließlich")
    (persuasive
     "must" "should" "need" "best" "never" "always" "imagine" "discover" "proven" "guaranteed" "now"
     "only" "free" "you" "your" "today" "join" "act" "don't" "deserve"
     "muss" "müssen" "sollten" "beste" "niemals" "immer" "stell" "entdecke" "jetzt" "nur" "gratis" "heute"))
  "Words that lean a text one way.  Each match counts one point.")

(defconst well-formed--positive
  '("good" "great" "excellent" "happy" "love" "like" "best" "better" "success" "successful" "easy" "clear"
    "nice" "wonderful" "glad" "thanks" "thank" "improve" "improved" "benefit" "win" "enjoy" "beautiful"
    "gut" "toll" "super" "prima" "glücklich" "Freude" "lieben" "besser" "Erfolg" "einfach" "danke" "schön"))
(defconst well-formed--negative
  '("bad" "poor" "wrong" "fail" "failed" "failure" "problem" "problems" "difficult" "hard" "error" "bug"
    "hate" "worse" "worst" "sad" "angry" "broken" "slow" "pain" "annoying" "issue" "unfortunately" "never"
    "schlecht" "falsch" "Fehler" "Problem" "Probleme" "schwierig" "kaputt" "langsam" "leider" "nie" "ärgerlich"))

(defun well-formed--tone (paras)
  "Tone of PARAS: plist :mix ((TONE . PERCENT)...), and :formality,
:confidence and :sentiment (0–100)."
  (let* ((text (mapconcat #'well-formed-para-text paras "\n"))
         (words (mapcar #'car (well-formed--words text)))
         (n (max 1 (length words)))
         (lower (mapcar #'downcase words))
         (bag (let ((h (make-hash-table :test #'equal))) (dolist (w lower) (cl-incf (gethash w h 0))) h))
         (count (lambda (list) (cl-loop for w in list sum (gethash (downcase w) bag 0))))
         (nominal (cl-count-if (lambda (w) (string-match-p "\\(?:tion\\|ment\\|ness\\|ity\\|ism\\|ance\\|ence\\|ung\\|heit\\|keit\\|ität\\)\\'" w)) lower))
         (contractions (cl-count-if (lambda (w) (string-match-p "['’]\\(?:t\\|re\\|ve\\|ll\\|m\\|d\\)\\'" w)) lower))
         (questions (cl-count ?? text))
         (exclaims (cl-count ?! text))
         (digits (let ((pos 0) (c 0)) (while (string-match "[0-9]+" text pos) (setq c (1+ c) pos (match-end 0))) c))
         (masked-runs (let ((pos 0) (c 0)) (while (string-match "\0+" text pos) (setq c (1+ c) pos (match-end 0))) c))
         (quotes (let ((pos 0) (c 0)) (while (string-match "[\"“„][^\"”“]\\{3,\\}[\"”“]" text pos) (setq c (1+ c) pos (match-end 0))) c))
         (past (cl-count-if (lambda (w) (string-match-p "[^e]ed\\'" w)) lower))
         (raw `((academic . ,(+ (funcall count (alist-get 'academic well-formed--tone-lexicon)) (* 0.5 nominal)))
                (technical . ,(+ (funcall count (alist-get 'technical well-formed--tone-lexicon)) (* 0.5 digits) masked-runs))
                (business . ,(funcall count (alist-get 'business well-formed--tone-lexicon)))
                (conversational . ,(+ (funcall count (alist-get 'conversational well-formed--tone-lexicon))
                                      contractions questions))
                (storytelling . ,(+ (funcall count (alist-get 'storytelling well-formed--tone-lexicon)) (* 0.5 past) quotes))
                (persuasive . ,(+ (funcall count (alist-get 'persuasive well-formed--tone-lexicon)) exclaims))))
         (total (max 0.001 (apply #'+ (mapcar #'cdr raw))))
         (hedges (+ (funcall count '("maybe" "perhaps" "possibly" "probably" "somewhat" "think" "guess" "seems"
                                     "vielleicht" "eigentlich" "wohl" "irgendwie" "eher" "möglicherweise"))))
         (pos (funcall count well-formed--positive))
         (neg (funcall count well-formed--negative))
         (formal (+ nominal (funcall count (alist-get 'academic well-formed--tone-lexicon))))
         (informal (+ contractions exclaims (funcall count (alist-get 'conversational well-formed--tone-lexicon)))))
    (list :mix (sort (mapcar (lambda (r) (cons (car r) (* 100 (/ (cdr r) total)))) raw)
                     (lambda (a b) (> (cdr a) (cdr b))))
          :formality (round (* 100 (/ (+ formal 1.0) (+ formal informal 2.0))))
          :confidence (max 0 (round (- 100 (* 100 (/ (* 8.0 hedges) n)))))
          :sentiment (round (* 100 (/ (+ pos 1.0) (+ pos neg 2.0)))))))

;;;; Scores

(defun well-formed--scores (findings words)
  "Overall and per-category scores (0–100) from FINDINGS in WORDS words."
  (let ((per (lambda (fs)
               (let ((weight (cl-loop for f in fs sum (pcase (nth 3 f) ('error 4.0) ('warning 2.0) (_ 0.7)))))
                 (round (* 100 (exp (- (* 0.25 (/ (* 100 weight) (max 50 words)))))))))))
    (cons (cons 'overall (funcall per findings))
          (mapcar (lambda (c)
                    (cons (car c)
                          (funcall per (cl-remove-if-not
                                        (lambda (f) (eq (well-formed-rule-category (well-formed--rule (nth 2 f))) (car c)))
                                        findings))))
                  well-formed-categories))))

;;;; Drawing

(defun well-formed--bar (fraction width &optional face)
  "A bar FRACTION (0–1) of WIDTH columns, in eighths."
  (let* ((eighths (round (* 8 width (max 0 (min 1 fraction)))))
         (full (/ eighths 8)) (part (% eighths 8)))
    (propertize (concat (make-string full ?█)
                        (if (> part 0) (string (aref " ▏▎▍▌▋▊▉" part)) ""))
                'face (or face 'well-formed-report-bar))))

(defun well-formed--spark (values &optional max)
  (let ((max (or max (apply #'max 1 values))))
    (mapconcat (lambda (v) (string (aref "▁▂▃▄▅▆▇█" (min 7 (floor (* 7.99 (/ (float v) max)))))))
               values "")))

(defun well-formed--score-face (score)
  (cond ((>= score 85) 'success) ((>= score 65) 'warning) (t 'error)))

(defun well-formed--jump-button (label buf pos &optional help)
  (insert-text-button label 'action (lambda (_) (pop-to-buffer buf) (goto-char pos))
                      'follow-link t 'help-echo (or help "Go there")))

;;;###autoload
(defun well-formed-report (&optional beg end)
  "A report on the buffer (or region): scores, readability, tone, statistics."
  (interactive (when (use-region-p) (list (region-beginning) (region-end))))
  (let* ((buf (current-buffer))
         (beg (or beg (point-min))) (end (or end (point-max)))
         (findings (cl-remove-if-not (lambda (f) (and (>= (car f) beg) (<= (cadr f) end)))
                                     (well-formed-check)))
         (paras (cl-remove-if-not (lambda (p) (and (>= (well-formed-para-beg p) beg) (< (well-formed-para-beg p) end)))
                                  (plist-get well-formed--doc :paras)))
         (prose (cl-remove-if (lambda (p) (eq (well-formed-para-kind p) 'heading)) paras))
         (lang (let ((de (cl-count "de" prose :key #'well-formed-para-lang :test #'equal)))
                 (if (> de (/ (length prose) 2)) "de" "en")))
         (sentences (cl-loop for p in prose append
                             (mapcar (lambda (s) (list (+ (well-formed-para-beg p) (car s))
                                                       (well-formed--word-count (well-formed-para-text p) (car s) (cdr s))))
                                     (well-formed-para-sentences p))))
         (sentences (cl-remove-if (lambda (s) (zerop (cadr s))) sentences))
         (words (cl-loop for p in prose append (mapcar #'car (well-formed--words (well-formed-para-text p)))))
         (nwords (length words))
         (unique (length (delete-dups (mapcar #'downcase (copy-sequence words)))))
         (read (well-formed--readability words (length sentences) lang))
         (tone (well-formed--tone prose))
         (scores (well-formed--scores findings nwords))
         (style (car (with-current-buffer buf (well-formed--document-settings))))
         (spent (gethash (or (buffer-file-name buf) (buffer-name buf)) (well-formed--times) 0)))
    (with-current-buffer (get-buffer-create "*well-formed report*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "%s" (buffer-name buf)) 'face '(:weight bold :height 1.3))
                (format "   %s · %s style\n\n" (if (equal lang "de") "German" "English") style))
        ;; Scores
        (insert (propertize "Scores\n" 'face 'well-formed-report-heading))
        (pcase-dolist (`(,cat . ,score) scores)
          (insert (format "  %-12s " (if (eq cat 'overall) "Overall" (alist-get cat well-formed-categories)))
                  (propertize (format "%3d " score) 'face (well-formed--score-face score))
                  (well-formed--bar (/ score 100.0) 30 (well-formed--score-face score))
                  (if (eq cat 'overall) ""
                    (format "  %d" (cl-count-if (lambda (f) (eq (well-formed-rule-category (well-formed--rule (nth 2 f))) cat))
                                                findings)))
                  "\n"))
        ;; Counts
        (insert "\n" (propertize "Text\n" 'face 'well-formed-report-heading)
                (format "  %d words · %d unique (%.0f%% variety) · %d sentences · %d paragraphs · %d characters\n"
                        nwords unique (* 100 (/ (float unique) (max 1 nwords))) (length sentences) (length prose)
                        (- end beg))
                (format "  Reading %s · speaking %s · writing so far %s\n"
                        (well-formed--duration (* 60 (/ nwords 238.0)))
                        (well-formed--duration (* 60 (/ nwords 150.0)))
                        (if (> spent 0) (well-formed--duration spent) "not tracked yet"))
                (format "  %.1f words per sentence · %.1f letters per word\n"
                        (/ (float nwords) (max 1 (length sentences)))
                        (/ (float (apply #'+ (mapcar #'length words))) (max 1 nwords))))
        (when-let* ((longest (car (sort (copy-sequence sentences) (lambda (a b) (> (cadr a) (cadr b)))))))
          (insert "  Longest sentence: ")
          (well-formed--jump-button (format "%d words" (cadr longest)) buf (car longest))
          (insert "\n"))
        ;; Readability
        (let ((ease (alist-get 'ease read)))
          (insert "\n" (propertize "Readability\n" 'face 'well-formed-report-heading)
                  (format "  %s %5.1f  " (if (equal lang "de") "Amstad reading ease " "Flesch reading ease") ease)
                  (well-formed--bar (/ (max 0 ease) 100.0) 20 (well-formed--score-face (+ ease 25)))
                  (format "  %s\n" (well-formed--ease-band ease)))
          (if (equal lang "de")
              (insert (format "  LIX %.0f (%s) · Wiener Sachtextformel %.1f (Schulstufe)\n"
                              (alist-get 'lix read)
                              (let ((l (alist-get 'lix read)))
                                (cond ((< l 30) "sehr leicht") ((< l 40) "leicht") ((< l 50) "mittel")
                                      ((< l 60) "schwer") (t "sehr schwer")))
                              (alist-get 'wstf read)))
            (insert (format "  Grade level: Flesch–Kincaid %.1f · Gunning fog %.1f · SMOG %.1f · Coleman–Liau %.1f · ARI %.1f\n"
                            (alist-get 'fk-grade read) (alist-get 'fog read) (alist-get 'smog read)
                            (alist-get 'coleman-liau read) (alist-get 'ari read))
                    (format "  LIX %.0f\n" (alist-get 'lix read)))))
        ;; Tone
        (insert "\n" (propertize "Tone (from word statistics)\n" 'face 'well-formed-report-heading))
        (pcase-dolist (`(,name . ,pct) (plist-get tone :mix))
          (insert (format "  %-15s %3.0f%% " name pct) (well-formed--bar (/ pct 100.0) 30) "\n"))
        (cl-flet ((scale (label low high v)
                    (insert (format "  %-15s %s %s %s  %d\n" label (string-pad low 9 nil t)
                                    (let ((pos (round (* 0.2 v))))
                                      (concat (make-string pos ?─) (propertize "●" 'face 'well-formed-report-bar)
                                              (make-string (- 20 pos) ?─)))
                                    high v))))
          (scale "Formality" "informal" "formal" (plist-get tone :formality))
          (scale "Confidence" "tentative" "confident" (plist-get tone :confidence))
          (scale "Sentiment" "negative" "positive" (plist-get tone :sentiment)))
        ;; Plots
        (when sentences
          (insert "\n" (propertize "Sentence lengths through the text\n" 'face 'well-formed-report-heading) "  ")
          (let ((lengths (mapcar #'cadr sentences)))
            (cl-loop for s in sentences
                     for ch across (well-formed--spark lengths)
                     do (well-formed--jump-button (string ch) buf (car s) (format "%d words" (cadr s))))
            (insert "\n\n" (propertize "Histogram\n" 'face 'well-formed-report-heading))
            (let* ((bins '((1 . 8) (9 . 15) (16 . 22) (23 . 30) (31 . 40) (41 . 1000)))
                   (counts (mapcar (lambda (b) (cl-count-if (lambda (l) (<= (car b) l (cdr b))) lengths)) bins))
                   (top (apply #'max 1 counts)))
              (cl-loop for b in bins for c in counts
                       do (insert (format "  %-7s %3d " (if (> (cdr b) 100) (format "%d+" (car b)) (format "%d–%d" (car b) (cdr b))) c)
                                  (well-formed--bar (/ (float c) top) 30) "\n")))))
        (when (cdr prose)
          (insert "\n" (propertize "Reading ease per paragraph\n" 'face 'well-formed-report-heading) "  ")
          (let ((eases (mapcar (lambda (p)
                                 (let ((ws (mapcar #'car (well-formed--words (well-formed-para-text p)))))
                                   (max 0 (min 100 (alist-get 'ease (well-formed--readability
                                                                    ws (max 1 (length (well-formed-para-sentences p)))
                                                                    (well-formed-para-lang p)))))))
                               prose)))
            (cl-loop for p in prose for ch across (well-formed--spark eases 100)
                     for e in eases
                     do (well-formed--jump-button (string ch) buf (well-formed-para-beg p) (format "reading ease %d" (round e)))))
          (insert "   (higher is easier)\n"))
        ;; Findings by rule
        (when findings
          (insert "\n" (propertize "Findings\n" 'face 'well-formed-report-heading))
          (let ((groups (seq-group-by (lambda (f) (nth 2 f)) findings)))
            (pcase-dolist (`(,id . ,fs) (sort groups (lambda (a b) (> (length (cdr a)) (length (cdr b))))))
              (insert "  ")
              (insert-text-button (format "%-18s" id) 'action (lambda (_) (well-formed-explain id))
                                  'follow-link t 'help-echo "Explain the rule")
              (insert (format " %3d  " (length fs)))
              (dolist (f (seq-take fs 8))
                (well-formed--jump-button (format "l%d" (with-current-buffer buf (line-number-at-pos (car f)))) buf (car f) (nth 4 f))
                (insert " "))
              (insert "\n"))))
        ;; Spelling is jinx's (it runs alongside, with its own dictionaries).
        (when-let* (((with-current-buffer buf (bound-and-true-p jinx-mode)))
                    ((fboundp 'jinx--force-overlays))
                    (typos (with-current-buffer buf (funcall 'jinx--force-overlays beg end))))
          (insert "\n" (propertize (format "Spelling (jinx): %d\n" (length typos)) 'face 'well-formed-report-heading) "  ")
          (dolist (o (seq-take typos 20))
            (well-formed--jump-button (with-current-buffer buf
                                        (buffer-substring-no-properties (overlay-start o) (overlay-end o)))
                                      buf (overlay-start o))
            (insert " "))
          (insert "\n"))
        ;; Words
        (let ((counts (make-hash-table :test #'equal)) top)
          (dolist (w words)
            (let ((k (downcase w)))
              (when (and (> (length k) 3) (not (member k well-formed-overused-ignore)))
                (cl-incf (gethash k counts 0)))))
          (maphash (lambda (k v) (push (cons k v) top)) counts)
          (setq top (seq-take (sort top (lambda (a b) (> (cdr a) (cdr b)))) 12))
          (when top
            (insert "\n" (propertize "Words used most\n" 'face 'well-formed-report-heading))
            (dolist (e top)
              (insert (format "  %-18s %3d " (car e) (cdr e)) (well-formed--bar (/ (float (cdr e)) (cdar top)) 20) "\n"))))
        (insert "\n" (propertize "g refresh · q quit · RET/click a bar, line or rule" 'face 'shadow) "\n")
        (goto-char (point-min))
        (well-formed-report-mode)
        (setq-local well-formed--report-source (list buf beg end)))
      (pop-to-buffer (current-buffer)))))

(define-derived-mode well-formed-report-mode special-mode "WF Report"
  "The well-formed report."
  (setq-local revert-buffer-function
              (lambda (&rest _)
                (pcase-let ((`(,buf ,beg ,end) well-formed--report-source))
                  (with-current-buffer buf (well-formed-report beg end))))))

;;;; In the mode line: the score, and words written today

(defcustom well-formed-mode-line t
  "Show the buffer's score (and words written today) in the mode line."
  :type 'boolean :group 'well-formed)

(defcustom well-formed-daily-goal nil
  "Words to write per file and day; the mode line shows the way there."
  :type '(choice (const :tag "None" nil) natnum) :group 'well-formed)

(defcustom well-formed-words-file
  (expand-file-name "well-formed-words.eld" (file-name-directory well-formed-ignore-file))
  "Where each file's word count at its first check of the day is kept."
  :type 'file :group 'well-formed)

(defvar well-formed--day-start nil "Hash: file → (DATE . WORDS at the day's first check).")
(defvar-local well-formed--mode-line nil "This buffer's mode line text, made after each check.")
(put 'well-formed--mode-line 'risky-local-variable t)

(defun well-formed--day-start ()
  (or well-formed--day-start
      (setq well-formed--day-start
            (let ((h (make-hash-table :test #'equal)))
              (when (file-readable-p well-formed-words-file)
                (ignore-errors
                  (with-temp-buffer
                    (insert-file-contents well-formed-words-file)
                    (pcase-dolist (`(,f . ,v) (read (current-buffer))) (puthash f v h)))))
              h))))

(defun well-formed--save-day-start ()
  (when well-formed--day-start
    (make-directory (file-name-directory well-formed-words-file) t)
    (let ((today (format-time-string "%F")) alist)
      ;; Only today's: older ones would never be read again.
      (maphash (lambda (k v) (when (equal (car v) today) (push (cons k v) alist))) well-formed--day-start)
      (with-temp-file well-formed-words-file (prin1 alist (current-buffer))))))

(add-hook 'kill-emacs-hook #'well-formed--save-day-start)

(defun well-formed--words-today (words)
  "Words written in this buffer today: WORDS less its count at the day's
first check (never below 0)."
  (let* ((key (or buffer-file-name (buffer-name)))
         (today (format-time-string "%F"))
         (start (gethash key (well-formed--day-start))))
    (unless (equal (car start) today)
      (puthash key (setq start (cons today words)) (well-formed--day-start)))
    (max 0 (- words (cdr start)))))

(defun well-formed--update-mode-line (findings)
  "After a check: the score from FINDINGS, and today's words, for the mode line."
  (when well-formed-mode-line
    (let* ((prose (cl-remove-if (lambda (p) (eq (well-formed-para-kind p) 'heading))
                                (plist-get well-formed--doc :paras)))
           (words (cl-loop for p in prose sum (well-formed--word-count (well-formed-para-text p))))
           (scores (well-formed--scores findings words))
           (score (cdr (assq 'overall scores)))
           (today (well-formed--words-today words))
           (goal well-formed-daily-goal))
      (setq well-formed--mode-line
            (concat
             (propertize (format "✎%d" score)
                         'face (well-formed--score-face score)
                         'help-echo (format "Writing score %d (%s)\n%d words, %d today%s\nmouse-1: the report"
                                            score
                                            (mapconcat (lambda (c) (format "%s %d" (car c) (cdr c)))
                                                       (cdr scores) ", ")
                                            words today
                                            (if goal (format " of %d" goal) ""))
                         'mouse-face 'mode-line-highlight
                         'local-map (make-mode-line-mouse-map 'mouse-1 #'well-formed-report))
             (cond ((and goal (>= today goal)) (propertize (format " +%d ✓" today) 'face 'success))
                   (goal (format " +%d/%d" today goal))
                   ((> today 0) (format " +%d" today))
                   (t "")))))
    (force-mode-line-update)))

(add-hook 'well-formed-after-check-functions #'well-formed--update-mode-line)

(defvar well-formed--mode-line-entry
  '(well-formed-mode (well-formed--mode-line ("" well-formed--mode-line " ")))
  "The mode line's entry (in `mode-line-misc-info', which doom-modeline shows).")

(unless (member well-formed--mode-line-entry mode-line-misc-info)
  (push well-formed--mode-line-entry mode-line-misc-info))

(provide 'well-formed-report)
;;; well-formed-report.el ends here
