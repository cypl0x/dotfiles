;;; well-formed-rules.el --- The rules well-formed checks -*- lexical-binding: t; -*-
;;
;;; Commentary:
;;
;; Grouped as Grammarly groups its cards:
;;   correctness   mistakes: repeated words, a/an, spacing, confused words,
;;                 capitalization, German das/dass and common misspellings
;;   clarity       wordiness, redundancy, long or hard sentences, passive
;;                 voice, nominalizations, complex words
;;   engagement    clichés, bland words, overused words, monotonous starts
;;   delivery      hedging, informal words, jargon, inclusive language, tone
;;   consistency   one spelling, hyphenation, quote style, list commas per
;;                 document (whichever the document uses more wins)
;;
;; Every rule's lists are data: add to them with `add-to-list' on the
;; variable before well-formed loads, or define a new rule with
;; `well-formed-define-rule'.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'well-formed)
(require 'time-date)

(declare-function well-formed-phrases "well-formed" (table message &optional case-sensitive))
(declare-function well-formed-regexps "well-formed" (table))
(declare-function well-formed-quote "well-formed" (s))
(declare-function well-formed--words "well-formed" (text &optional beg end))
(declare-function well-formed--word-count "well-formed" (text &optional beg end))
(declare-function well-formed--syllables "well-formed" (word))
(declare-function well-formed--match-case "well-formed" (template replacement))
(declare-function well-formed-para-text "well-formed" (para))
(declare-function well-formed-para-kind "well-formed" (para))
(declare-function well-formed-para-lang "well-formed" (para))
(declare-function well-formed-para-style "well-formed" (para))
(declare-function well-formed-para-sentences "well-formed" (para))
(declare-function well-formed-para-beg "well-formed" (para))
(defvar well-formed--syntax-table)
(defvar well-formed-document-functions)

;;;; Correctness

(well-formed-define-rule repeated-word
  :category 'correctness :level 'error
  :doc "The same word twice in a row, usually a slip while editing."
  :examples '(("the the result" . "the result"))
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) (pos 0) out (case-fold-search t))
      (with-syntax-table well-formed--syntax-table
        (while (string-match "\\<\\([[:alpha:]]+\\)\\([ \t\n]+\\)\\(\\1\\)\\>" text pos)
          (let ((w (downcase (match-string 1 text))))
            (unless (member w '("had" "that" "das" "die" "der" "sie" "is" "ha" "bye" "so" "very" "no" "yes" "ja" "nein" "really"))
              (push (list (match-beginning 2) (match-end 3)
                          (format "Repeated word: %s" (well-formed-quote (match-string 0 text)))
                          (list ""))
                    out)))
          (setq pos (match-end 1))))
      (nreverse out))))

(defconst well-formed--an-exceptions
  "\\`\\(?:uni\\|use\\|usu\\|uti\\|ura\\|ure\\|uro\\|eu\\|ewe\\|one\\b\\|once\\|ubiq\\|uga\\|ukr\\|unanim\\)"
  "Vowel letters that sound like consonants: a university, a one-off.")
(defconst well-formed--a-exceptions "\\`\\(?:hour\\|honest\\|honor\\|honour\\|heir\\)"
  "Consonant letters that sound like vowels: an hour.")

(defun well-formed--wants-an (word)
  "Whether WORD takes \"an\", by its first sound (roughly)."
  (let ((case-fold-search nil) (w word))
    (cond
     ;; Acronyms said letter by letter: an SQL, a URL is said "you-are-el".
     ((string-match-p "\\`[[:upper:]]\\{2,5\\}s?\\'" w)
      (and (not (member w '("NASA" "NATO" "UNESCO" "UNICEF" "UEFA" "OPEC" "FIFA" "NAFTA" "SCSI" "UTF" "URL" "USB" "UI" "UX" "UUID")))
           (string-match-p "\\`[AEFHILMNORSX]" w)))
     ((string-match-p "\\`[0-9]" w) (string-match-p "\\`\\(?:8\\|11\\|18\\)" w))
     (t (let ((d (downcase w)))
          (cond ((string-match-p well-formed--a-exceptions d) t)
                ((string-match-p well-formed--an-exceptions d) nil)
                (t (string-match-p "\\`[aeiou]" d))))))))

(well-formed-define-rule article
  :category 'correctness :level 'error :langs '("en")
  :doc "\"a\" before consonant sounds, \"an\" before vowel sounds (what you
hear, not the letter): a university, an hour, an SQL query."
  :examples '(("a apple" . "an apple") ("an university" . "a university") ("a hour" . "an hour"))
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) (pos 0) out (case-fold-search nil))
      (with-syntax-table well-formed--syntax-table
        (while (string-match "\\<\\([Aa]n?\\)[ \t\n]+\\([[:alnum:]][[:alnum:]-]*\\)" text pos)
          (let* ((art (match-string 1 text)) (word (match-string 2 text))
                 (an (well-formed--wants-an word))
                 (want (if an "an" "a")))
            (unless (or (string= (downcase art) want)
                        ;; "A" as a letter or label: "Plan A", "A and B".
                        (and (string= art "A") (string-match-p "\\`\\(?:and\\|or\\|to\\|is\\)\\'" word))
                        ;; "… like text a\nAnd shows": a sentence break went missing, not the article
                        (string-match-p "\\`\\(?:And\\|But\\|Or\\|So\\|The\\|It\\|I\\)\\'" word))
              (push (list (match-beginning 1) (match-end 1)
                          (format "Use %s before %s" (well-formed-quote want) (well-formed-quote word))
                          (list (well-formed--match-case art want)))
                    out)))
          (setq pos (match-end 1))))
      (nreverse out))))

(well-formed-define-rule spacing
  :category 'correctness :level 'warning
  :doc "A space before punctuation, none after it, or several between words."
  :examples '(("Hello , world" . "Hello, world") ("one,two" . "one, two"))
  :function
  (well-formed-regexps
   '(("[[:alpha:]\0]\\([ \t]+\\)[,;:.!?]\\(?:[[:space:]]\\|\\'\\)" "Space before punctuation" "" 1)
     ("[[:alpha:]]\\([,;]\\)[[:alpha:]]" "Missing space after %s" "\\1 " 1)
     ("[[:lower:]]\\(\\.\\)[[:upper:]][[:lower:]]" "Missing space after the period" ". " 1 t)
     ("[[:alpha:],]\\(  +\\)[[:alpha:]]" "Several spaces between words" " " 1))))

(well-formed-define-rule punctuation
  :category 'correctness :level 'warning
  :doc "Doubled punctuation (an ellipsis has three dots: … or ...)."
  :examples '(("Really,, yes" . "Really, yes") ("the end.." . "the end."))
  :function
  (well-formed-regexps
   '(("\\([,;:]\\)\\1+" "Doubled punctuation %s" "\\1")
     ("[^.]\\(\\.\\.\\)\\(?:[^.]\\|\\'\\)" "Two periods: one, or an ellipsis (…)?" "." 1)
     ("\\([!?]\\{2,\\}\\)" "Several %s: one is enough" (lambda (m) (substring m 0 1)) 1))))

(defvar well-formed-lowercase-names
  '("npm" "git" "nix" "systemd" "zsh" "bash" "vim" "pnpm" "yarn" "cargo" "rustc" "gcc" "make" "grep" "sed" "awk" "curl" "ssh" "sudo" "eglot" "magit" "jq" "fd" "rg" "tmux")
  "Names written in lower case, even at the start of a sentence.")

(well-formed-define-rule capitalization
  :category 'correctness :level 'warning
  :doc "A sentence starts with a capital letter; in English \"I\" is always
capital, and so are days and months."
  :examples '(("it works. it is fast." . "It works. It is fast.") ("then i left" . "then I left")
              ("on monday" . "on Monday"))
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) out (case-fold-search nil))
      (with-syntax-table well-formed--syntax-table
        (unless (eq (well-formed-para-kind para) 'heading)
          (cl-loop for (b . _e) in (well-formed-para-sentences para)
                   for i from 0
                   do (when (eql b (string-match "[\"'“‘(]*\\([[:lower:]][[:alpha:]]*\\)\\([^[:space:]]*\\)" text b))
                        (let ((w (match-string 1 text)) (rest (match-string 2 text))
                              (wb (match-beginning 1)) (we (match-end 1)))
                          (when (and
                                 ;; identifiers (macOS, eBay, npm's, foo.el), not words
                                 (not (string-match-p "[[:upper:][:digit:]_./]" w))
                                 (not (equal w "i"))
                                 (not (member w well-formed-lowercase-names))
                                 (string-match-p "\\`[,;:.!?)\"”’]*\\'" rest)
                                 ;; an item's first words may be a fragment by design
                                 (or (> i 0) (eq (well-formed-para-kind para) 'prose)))
                            (push (list wb we "Start the sentence with a capital letter"
                                        (list (concat (upcase (substring w 0 1)) (substring w 1))))
                                  out))))))
        (when (equal (well-formed-para-lang para) "en")
          (let ((pos 0))
            (while (string-match "\\(?:^\\|[[:space:]\"(]\\)\\(i\\)\\(?:[[:space:],;:.!?]\\|'[mdv]\\|'ll\\)" text pos)
              (unless (and (< (match-end 1) (1- (length text)))
                           (string-prefix-p ".e" (substring text (match-end 1))))
                (push (list (match-beginning 1) (match-end 1) "\"I\" is capitalized" (list "I")) out))
              (setq pos (match-end 1))))
          (let ((pos 0)
                (re "\\<\\(monday\\|tuesday\\|wednesday\\|thursday\\|friday\\|saturday\\|sunday\\|january\\|february\\|april\\|june\\|july\\|august\\|september\\|october\\|november\\|december\\)\\>"))
            (while (string-match re text pos)
              (let ((w (match-string 1 text)))
                (push (list (match-beginning 1) (match-end 1) (format "Capitalize %s" (well-formed-quote w))
                            (list (capitalize w)))
                      out))
              (setq pos (match-end 0))))))
      (nreverse out))))

(defvar well-formed-confused-en
  '(("\\<\\(could\\|should\\|would\\|must\\|might\\) of\\>" "%s → %s" "\\1 have")
    ("\\<\\(more\\|less\\|better\\|worse\\|rather\\|fewer\\|greater\\|larger\\|smaller\\|higher\\|lower\\|faster\\|slower\\|easier\\|harder\\|bigger\\|longer\\|shorter\\|older\\|younger\\|stronger\\|weaker\\|cheaper\\|other\\) then\\>"
     "Comparisons take \"than\": %s → %s" "\\1 than")
    ("\\<your \\(welcome\\|going\\|right\\|wrong\\|not\\|being\\|doing\\|the best\\)\\>" "%s → %s" "you're \\1")
    ("\\<its \\(a\\|an\\|not\\|been\\|going\\|very\\|true\\|important\\|possible\\|clear\\|likely\\)\\>"
     "\"it's\" = it is: %s → %s" "it's \\1")
    ;; "its" before what can't follow a possessive: an article, a
    ;; determiner, an adverb, a state.
    ("\\<its \\(the\\|my\\|your\\|our\\|their\\|this\\|that\\|just\\|also\\|still\\|already\\|really\\|so\\|too\\|ok\\|okay\\|fine\\|done\\|here\\|there\\|now\\|almost\\|probably\\|definitely\\|always\\|never\\|enough\\)\\>"
     "\"it's\" = it is: %s → %s" "it's \\1")
    ("\\<it's \\(own\\|self\\)\\>" "Possessive \"its\": %s → %s" "its \\1")
    ;; "it's" before what a thing has.
    ("\\<it's \\(name\\|value\\|size\\|color\\|colour\\|purpose\\|contents\\|parent\\|children\\|members\\|origin\\|role\\|job\\|output\\|input\\|length\\|width\\|height\\|source\\|default\\|author\\|owner\\|users\\)\\>"
     "Possessive \"its\": %s → %s" "its \\1")
    ("\\<\\(its'\\)" "%s is never right → %s" "its")
    ("\\<their \\(is\\|are\\|was\\|were\\|will be\\|has been\\)\\>" "%s → %s" "there \\1")
    ("\\<there \\(own\\)\\>" "%s → %s" "their \\1")
    ("\\<loose \\(weight\\|track\\|control\\|interest\\|the\\)\\>" "\"lose\", not \"loose\": %s → %s" "lose \\1")
    ("\\<alot\\>" "%s → %s" "a lot")
    ("\\<irregardless\\>" "%s → %s" "regardless")
    ("\\<per say\\>" "%s → %s" "per se")
    ("\\<for all intensive purposes\\>" "%s → %s" "for all intents and purposes")
    ("\\<tow the line\\>" "%s → %s" "toe the line")
    ("\\<case and point\\>" "%s → %s" "case in point")
    ("\\<free reign\\>" "%s → %s" "free rein")
    ("\\<sneak peak\\>" "%s → %s" "sneak peek")
    ("\\<peaked? \\(my\\|your\\|his\\|her\\|their\\|our\\) interest\\>" "\"pique\" interest: %s → %s" "piqued \\1 interest")
    ("\\<baited breath\\>" "%s → %s" "bated breath")
    ("\\<deep-seeded\\>" "%s → %s" "deep-seated")
    ("\\<one in the same\\>" "%s → %s" "one and the same")
    ("\\<nip it in the butt\\>" "%s → %s" "nip it in the bud")
    ("\\<first-come,? first-serve\\>" "%s → %s" "first-come, first-served")
    ("\\<could care less\\>" "You mean you couldn't: %s → %s" "couldn't care less")
    ("\\<on accident\\>" "%s → %s" "by accident")
    ("\\<in regards to\\>" "%s → %s" "regarding")
    ("\\<\\(an\\|the\\) affect \\(of\\|on\\)\\>" "The noun is \"effect\": %s → %s" "\\1 effect \\2")
    ("\\<less \\(people\\|items\\|things\\|words\\|files\\|lines\\|errors\\|bugs\\|steps\\|users\\|calls\\|tests\\)\\>"
     "Countable: %s → %s" "fewer \\1")
    ("\\<the reason is because\\>" "%s → %s" "the reason is that")
    ("\\<try and \\([[:alpha:]]+\\)" "%s → %s" "try to \\1")
    ("\\<suppose to\\>" "%s → %s" "supposed to")
    ("\\<use to \\(be\\|have\\|do\\|go\\|think\\|live\\|work\\)\\>" "%s → %s" "used to \\1")
    ("\\<who's \\(car\\|house\\|book\\|idea\\|turn\\|fault\\|job\\)\\>" "Possessive \"whose\": %s → %s" "whose \\1")
    ("\\<every since\\>" "%s → %s" "ever since")
    ("\\<might of\\>" "%s → %s" "might have"))
  "Confused English words: (REGEXP MESSAGE FIX).")

(well-formed-define-rule confused-word
  :category 'correctness :level 'error :langs '("en")
  :doc "Words often swapped for one that sounds the same: then/than, its/it's,
your/you're, their/there, lose/loose, could of, and fixed phrases said
wrong (free rein, case in point)."
  :examples '(("better then before" . "better than before") ("its a bug" . "it's a bug")
              ("should of known" . "should have known"))
  :function (lambda (para) (funcall (well-formed-regexps well-formed-confused-en) para)))

(well-formed-define-rule false-friend
  :category 'correctness :level 'warning :langs '("en")
  :doc "English as German speakers write it: since/for with durations, \"make
a photo\", uncountable nouns in the plural (informations, advices),
\"explain me\", \"discuss about\", \"on the picture\"."
  :examples '(("since three years" . "for three years") ("informations" . "information")
              ("explain me" . "explain to me"))
  :function
  (well-formed-regexps
   '(("\\<since \\(\\(?:[0-9]+\\|one\\|two\\|three\\|four\\|five\\|six\\|seven\\|eight\\|nine\\|ten\\|many\\|several\\|a few\\) \\(?:years?\\|months?\\|weeks?\\|days?\\|hours?\\|minutes?\\)\\)\\>"
      "A duration takes \"for\" (\"since\" needs a point in time): %s → %s" "for \\1")
     ("\\<\\(make\\|made\\|making\\|makes\\) \\(a \\)?\\(photo\\|picture\\|photos\\|pictures\\)\\>" "%s → %s"
      (lambda (m) (replace-regexp-in-string "\\<ma\\(?:ke\\|de\\|king\\|kes\\)\\>"
                                            (lambda (v) (pcase v ("make" "take") ("made" "took") ("making" "taking") (_ "takes")))
                                            m)))
     ("\\<\\(information\\|advice\\|knowledge\\|feedback\\|software\\|hardware\\|equipment\\|homework\\|furniture\\|luggage\\|evidence\\|research\\)s\\>"
      "Uncountable in English: %s → %s" "\\1")
     ("\\<stuffs\\>" "Uncountable: %s → %s" "stuff")
     ("\\<explain \\(me\\|us\\|him\\|her\\|them\\)\\>" "%s → %s" "explain to \\1")
     ("\\<discuss about\\>" "%s → %s" "discuss")
     ("\\<on the \\(picture\\|photo\\|image\\)\\>" "%s → %s" "in the \\1")
     ("\\<in the internet\\>" "%s → %s" "on the internet")
     ("\\<depends? of\\>" "%s → %s" (lambda (m) (replace-regexp-in-string "of\\'" "on" m)))
     ("\\<the most of the\\>" "%s → %s" "most of the")
     ("\\<I am agree\\>" "%s → %s" "I agree")
     ("\\<possibility to \\([[:alpha:]]+\\)" "Maybe: %s → %s" "opportunity to \\1")
     ("\\<\\(my\\|his\\|her\\|your\\|the\\) handy\\>" "\"Handy\" is German: %s → %s" "\\1 phone")
     ("\\<\\(my\\|his\\|her\\|your\\|our\\|the\\) chef\\>" "A chef cooks; \"Chef\" is the boss: %s → %s" "\\1 boss")
     ("\\<\\(actual\\) \\(version\\|state\\|status\\|situation\\|news\\|weather\\)\\>"
      "\"actual\" means real; \"aktuell\" is current: %s → %s" "current \\2")
     ("\\<consequent\\(ly\\)? \\(implemented\\|applied\\|used\\|followed\\)\\>"
      "\"konsequent\" is consistent(ly): %s → %s" "consistently \\2"))))

(well-formed-define-rule known-term
  :category 'correctness :level 'warning
  :doc "Names spelled the way their owners spell them."
  :examples '(("Github" . "GitHub") ("Javascript" . "JavaScript"))
  :function
  (let ((terms '("GitHub" "GitLab" "JavaScript" "TypeScript" "macOS" "iOS" "iPhone" "iPad" "NixOS"
                 "PostgreSQL" "MySQL" "SQLite" "YouTube" "LinkedIn" "PayPal" "WordPress" "LaTeX"
                 "OpenAI" "ChatGPT" "WebAssembly" "WebSocket" "OAuth" "JSON" "YAML" "TOML" "HTML" "CSS"
                 "Wi-Fi" "Bluetooth" "Hyprland" "Wayland" "systemd" "Tailscale" "Emacs" "Linux"
                 "Python" "Rust" "Haskell" "OCaml" "Node.js" "npm" "Docker" "Kubernetes" "GraphQL"
                 "ThinkPad" "DuckDuckGo" "Dropbox" "Lean" "Coq" "Rocq" "Agda" "Zig")))
    (let ((map (make-hash-table :test #'equal)))
      (dolist (term terms) (puthash (downcase term) term map))
      (let ((re (concat "\\<" (regexp-opt (mapcar #'downcase terms) t) "\\>")))
        (lambda (para)
          (let ((text (well-formed-para-text para)) (pos 0) out (case-fold-search t))
            (with-syntax-table well-formed--syntax-table
              (while (string-match re text pos)
                (let* ((m (match-string 0 text)) (right (gethash (downcase m) map)))
                  (unless (or (string= m right)
                              ;; part of an identifier: latex-mode, nixos/configuration.nix
                              (and (> (match-beginning 0) 0)
                                   (memq (aref text (1- (match-beginning 0))) '(?- ?_ ?/ ?. ?@)))
                              (and (< (match-end 0) (length text))
                                   (memq (aref text (match-end 0)) '(?- ?_ ?/ ?@))
                                   (< (1+ (match-end 0)) (length text))
                                   (not (memq (aref text (1+ (match-end 0))) '(?\s ?\n))))
                              ;; plain words that are also names: "rust", "lean", "python" the snake
                              (and (string= m (downcase m))
                                   (member right '("Rust" "Lean" "Python" "Linux" "Emacs" "Docker" "Bluetooth" "Coq" "Zig" "Agda")))
                              (and (string= m (upcase m)) (> (length m) 4) (not (member right '("JSON" "YAML" "TOML" "HTML")))))
                    (push (list (match-beginning 0) (match-end 0)
                                (format "Spelled %s" (well-formed-quote right)) (list right))
                          out)))
                (setq pos (match-end 0))))
            (nreverse out)))))))

;;;;; German

(well-formed-define-rule dass
  :category 'correctness :level 'error :langs '("de")
  :doc "\"dass\" leitet nach Verben des Sagens, Denkens, Wissens einen
Nebensatz ein; \"das\" ist Artikel oder Relativpronomen (ersetzbar
durch \"welches\")."
  :examples '(("Ich glaube, das er kommt." . "Ich glaube, dass er kommt."))
  :function
  (well-formed-regexps
   '(("\\<\\(?:sag\\w*\\|glaub\\w*\\|denk\\w*\\|hoff\\w*\\|weiß\\|wusste\\w*\\|wissen\\|meint?\\w*\\|behaupt\\w*\\|sicher\\|klar\\|wichtig\\|möglich\\|bekannt\\|scheint\\|zeigt?\\w*\\|bedeutet\\|erwart\\w*\\|merk\\w*\\|sehe?n?\\|finde\\|fand\\|so\\|ohne\\|statt\\|anstatt\\|sodass\\|damit\\),? \\(das\\) \\(?:ich\\|du\\|er\\|sie\\|es\\|wir\\|ihr\\|man\\|der\\|die\\|dies\\w*\\|jemand\\|niemand\\|alle\\|nicht\\|kein\\w*\\|mein\\w*\\|dein\\w*\\|unser\\w*\\)\\>"
      "Hier ist wohl \"dass\" gemeint (Konjunktion)" "dass" 1))))

(well-formed-define-rule seit-seid
  :category 'correctness :level 'error :langs '("de")
  :doc "\"seit\" ist zeitlich (seit gestern), \"seid\" ist die Verbform (ihr seid)."
  :examples '(("seid gestern" . "seit gestern") ("ihr seit" . "ihr seid"))
  :function
  (well-formed-regexps
   '(("\\<\\(seid\\) \\(?:gestern\\|heute\\|langem\\|kurzem\\|Jahren\\|Monaten\\|Wochen\\|Tagen\\|Stunden\\|[0-9]+\\|einige[mn]?\\|wann\\)\\>"
      "Zeitlich: \"seit\"" "seit" 1)
     ("\\<ihr \\(seit\\)\\>" "Verbform: \"seid\"" "seid" 1 t))))

(defvar well-formed-misspellings-de
  '(("Standart" . "Standard") ("vorraus" . "voraus") ("Vorraussetzung" . "Voraussetzung")
    ("wiederspiegeln" . "widerspiegeln") ("wiederspiegelt" . "widerspiegelt") ("Wiederspruch" . "Widerspruch")
    ("wiedersprechen" . "widersprechen") ("nähmlich" . "nämlich") ("Rhytmus" . "Rhythmus")
    ("Addresse" . "Adresse") ("Maschiene" . "Maschine") ("seperat" . "separat") ("Reperatur" . "Reparatur")
    ("Lizens" . "Lizenz") ("Agression" . "Aggression") ("Atmossphäre" . "Atmosphäre") ("brilliant" . "brillant")
    ("entgültig" . "endgültig") ("Gallerie" . "Galerie") ("Hobbies" . "Hobbys") ("Interresse" . "Interesse")
    ("Konkurenz" . "Konkurrenz") ("Silouette" . "Silhouette") ("Terasse" . "Terrasse") ("Tolleranz" . "Toleranz")
    ("Billiard" . "Billard") ("Wehrmutstropfen" . "Wermutstropfen") ("zuende" . "zu Ende")
    ("garnicht" . "gar nicht") ("garkein" . "gar kein") ("garkeine" . "gar keine") ("aufjedenfall" . "auf jeden Fall")
    ("Ziehharmonika" . "Ziehharmonika") ("einzigste" . "einzige") ("einzigster" . "einziger")
    ("optimalste" . "optimale") ("Rückantwort" . "Antwort") ("Packet" . "Paket") ("Pakete" . "Pakete")
    ("tod langweilig" . "todlangweilig") ("tod müde" . "todmüde") ("Tod müde" . "todmüde")
    ("wohlmöglich" . "womöglich") ("ebend" . "eben") ("Nachnahme" . "Nachname") ("Fußgängerweg" . "Fußweg")
    ("Ingeneur" . "Ingenieur") ("Kommision" . "Kommission") ("Komission" . "Kommission")
    ("Rethorik" . "Rhetorik") ("Rhetorig" . "Rhetorik") ("Satelit" . "Satellit") ("Stehgreif" . "Stegreif")
    ("Tipp-Ex" . "Tipp-Ex") ("tolerierbar" . "tolerierbar") ("Vakum" . "Vakuum") ("Zylinder" . "Zylinder")
    ("Sinn machen" . "Sinn ergeben") ("macht Sinn" . "ergibt Sinn") ("machte Sinn" . "ergab Sinn")
    ("macht keinen Sinn" . "ergibt keinen Sinn"))
  "Common German misspellings: (WRONG . RIGHT).")

(well-formed-define-rule misspelling-de
  :category 'correctness :level 'error :langs '("de")
  :doc "Häufige Falschschreibungen, die eine Rechtschreibprüfung oft
durchlässt (sie stehen in vielen Wörterbüchern), und \"Sinn machen\"."
  :examples '(("Standart" . "Standard") ("wiederspiegeln" . "widerspiegeln"))
  :function
  (let ((fn nil))
    (lambda (para)
      (unless fn
        (setq fn (well-formed-phrases (cl-remove-if (lambda (e) (equal (car e) (cdr e))) well-formed-misspellings-de)
                                      "%s → %s")))
      (funcall fn para))))

(well-formed-define-rule genitive-de
  :category 'correctness :level 'info :langs '("de")
  :doc "Präpositionen mit Genitiv in geschriebener Sprache: wegen des, trotz des."
  :examples '(("wegen dem Regen" . "wegen des Regens"))
  :function
  (well-formed-regexps
   '(("\\<\\(wegen\\|trotz\\|während\\|statt\\|anstatt\\|aufgrund\\) \\(dem\\)\\>"
      "Schriftsprachlich mit Genitiv: \"%s\" (des …s)" nil))))

(defun well-formed--unless-auxiliary-before (fn)
  "FN's findings, minus those right after an auxiliary or \"to\": in
\"does he go\", \"let it run\", \"make them have\" the verb is bare."
  (lambda (para)
    (let ((text (well-formed-para-text para)) (case-fold-search t))
      (cl-remove-if
       (lambda (f)
         (let ((before (substring text (max 0 (- (car f) 24)) (car f))))
           (string-match-p "\\<\\(?:does\\|did\\|do\\|can\\|could\\|will\\|would\\|shall\\|should\\|may\\|might\\|must\\|to\\|let\\|make\\|made\\|help\\|helps\\|watch\\|see\\|saw\\|hear\\|heard\\|have\\|had\\|if\\|that\\|lest\\)[[:space:]]+[[:alpha:]]+[[:space:]]+\\'" before)))
       (funcall fn para)))))

(well-formed-define-rule agreement
  :category 'correctness :level 'error :langs '("en")
  :doc "Subject and verb agree: he goes, they go; she has, we have; it
doesn't, they don't."
  :examples '(("he go home" . "he goes home") ("they has" . "they have") ("it don't" . "it doesn't"))
  :function
  (well-formed--unless-auxiliary-before
   (well-formed-regexps
   '(("\\<\\(?:[Hh]e\\|[Ss]he\\|[Ii]t\\) \\(go\\|do\\|have\\|want\\|need\\|like\\|make\\|take\\|know\\|think\\|work\\|seem\\|say\\|get\\|come\\|look\\|use\\|run\\)\\>\\(?: [[:alpha:]]\\)"
      "Third person: %s → %s"
      (lambda (v) (pcase v ("go" "goes") ("do" "does") ("have" "has") ("say" "says")
                    (_ (concat v "s"))))
      1 t)
     ("\\<\\(?:[Tt]hey\\|[Ww]e\\|[Yy]ou\\|I\\) \\(has\\|does\\|was\\|is\\|goes\\|wants\\|needs\\|seems\\)\\>"
      "%s → %s"
      (lambda (v) (pcase v ("has" "have") ("does" "do") ("was" "were") ("is" "are") ("goes" "go")
                    (_ (substring v 0 -1))))
      1 t)
     ("\\<\\(?:[Hh]e\\|[Ss]he\\|[Ii]t\\) \\(don't\\)\\>" "%s → %s" "doesn't" 1 t)
     ("\\<\\(?:[Tt]hey\\|[Ww]e\\|[Yy]ou\\|I\\) \\(doesn't\\)\\>" "%s → %s" "don't" 1 t)))))

(defconst well-formed--subordinators
  '("if" "when" "whenever" "because" "although" "though" "while" "since" "after" "before"
    "as" "unless" "once" "until" "whether" "even" "where" "wherever" "so" "yes" "no"
    "however" "therefore" "also" "then" "now" "here" "well" "ok" "okay" "sure" "oh")
  "First words of an opening clause that may end in a comma before a new one.")

(defconst well-formed--finite-verb
  "\\<\\(?:is\\|are\\|was\\|were\\|has\\|have\\|had\\|will\\|would\\|can\\|could\\|should\\|must\\|does\\|do\\|did\\|[[:alpha:]]+ed\\|[[:alpha:]]\\{3,\\}s\\)\\>"
  "Roughly, a word that makes a clause of its own.")

(well-formed-define-rule comma-splice
  :category 'correctness :level 'warning :langs '("en")
  :doc "Two sentences joined by a comma alone: a period, a semicolon or a
conjunction (and, but, so) belongs there.  Not after an opening clause
(If it rains, it pours) and not before \"that is\"."
  :examples '(("The build passed, it is ready." . "The build passed; it is ready."))
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) out (case-fold-search nil))
      (with-syntax-table well-formed--syntax-table
        (pcase-dolist (`(,sb . ,se) (well-formed-para-sentences para))
          (let ((pos sb))
            (while (and (string-match "\\(, \\)\\(\\(?:it\\|this\\|there\\|he\\|she\\|we\\|they\\|I\\|you\\) \\(?:is\\|are\\|was\\|were\\|has\\|have\\|had\\|will\\|would\\|can\\|could\\|should\\|must\\|does\\|did\\|seems\\|looks\\)\\>\\)"
                                      text pos)
                        (< (match-beginning 1) se))
              (let* ((cb (match-beginning 1)) (ce (match-end 1)) (rest (match-string 2 text))
                     (left (substring text sb cb))
                     (first (progn (setq pos (match-end 0))
                                   (downcase (or (car (split-string left "[^[:alpha:]']+" t)) "")))))
                (when (and (>= (length (split-string left "[[:space:]\0]+" t)) 3)
                           (not (member first well-formed--subordinators))
                           (not (string-match-p ",\\|\\<\\(?:and\\|but\\|or\\|so\\|which\\|who\\)\\>" left))
                           (let ((case-fold-search t)) (string-match-p well-formed--finite-verb left)))
                  (push (list cb ce
                              "Comma splice: two sentences joined by a comma"
                              (list "; " (concat ". " (if (string-prefix-p "I " rest) "I"
                                                        (upcase (substring rest 0 1))))))
                        out)))))))
      (setq out (nreverse out))
      ;; The period fix also capitalizes the next word: replace through it.
      (mapcar (lambda (f)
                (pcase-let ((`(,b ,e ,msg (,semi ,period)) f))
                  (list b (1+ e) msg (list (concat semi (substring text e (1+ e))) period))))
              out))))

(well-formed-define-rule apostrophe-plural
  :category 'correctness :level 'warning :langs '("en")
  :doc "Plurals take no apostrophe: the 1990s, two CDs, many APIs (the
apostrophe makes a possessive: NASA's mission)."
  :examples '(("in the 1990's" . "in the 1990s") ("two CD's" . "two CDs"))
  :function
  (well-formed-regexps
   '(("\\<\\([0-9]\\{2\\}[0-9]0\\|[0-9]0\\)\\('s\\)\\>" "Decades take no apostrophe: %s → %s"
      (lambda (_) "s") 2 t)
     ("\\<\\(?:many\\|several\\|some\\|few\\|all\\|these\\|those\\|multiple\\|two\\|three\\|four\\|five\\|six\\|seven\\|eight\\|nine\\|ten\\|[0-9]+\\) [[:upper:]]\\{2,\\}\\('s\\)\\>"
      "Plurals take no apostrophe: %s → %s" (lambda (_) "s") 1 t)
     ("\\<[[:upper:]]\\{2,\\}\\('s\\) \\(?:are\\|were\\|have\\)\\>"
      "Plurals take no apostrophe: %s → %s" (lambda (_) "s") 1 t))))

(well-formed-define-rule introductory-comma
  :category 'correctness :level 'warning :langs '("en")
  :doc "A sentence opened by a linking adverb or phrase sets it off with a
comma: However, …; For example, …"
  :examples '(("However we left." . "However, we left."))
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) out (case-fold-search nil)
          (re (concat "\\(" (regexp-opt '("However" "Therefore" "Moreover" "Furthermore" "Consequently"
                                         "Nevertheless" "Nonetheless" "Meanwhile" "Additionally" "Instead"
                                         "In addition" "For example" "For instance" "In fact" "As a result"
                                         "On the other hand" "In other words" "In contrast" "Otherwise"))
                      "\\)\\( \\)[[:alpha:]]")))
      (pcase-dolist (`(,b . ,_e) (well-formed-para-sentences para))
        (when (eql b (string-match re text b))
          (push (list (match-beginning 1) (match-end 1)
                      (format "Comma after %s" (well-formed-quote (match-string 1 text)))
                      (list (concat (match-string 1 text) ",")))
                out)))
      (nreverse out))))

(well-formed-define-rule comma-de
  :category 'correctness :level 'error :langs '("de")
  :doc "Vor Nebensätzen steht ein Komma: …, dass; …, weil; …, obwohl."
  :examples '(("Ich weiß dass es stimmt." . "Ich weiß, dass es stimmt."))
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) (pos 0) out (case-fold-search nil))
      (with-syntax-table well-formed--syntax-table
        (while (string-match "\\([[:alpha:]]\\)\\( \\)\\(dass\\|weil\\|obwohl\\|sodass\\|damit\\|nachdem\\|bevor\\|während\\|falls\\|sofern\\|wobei\\)\\> [[:alpha:]]" text pos)
          (let* ((conj (match-string 3 text))
                 (before (save-match-data
                           (let ((s (substring text (max 0 (- (match-beginning 2) 12)) (match-beginning 2))))
                             (and (string-match "\\([[:alpha:]]+\\)\\'" s) (match-string 1 s))))))
            ;; "so dass", "ohne dass", "als dass", "auch wenn": no comma inside;
            ;; "damit"/"während"/"bevor" are also adverbs and prepositions.
            (unless (or (member before '("so" "ohne" "als" "statt" "anstatt" "außer" "und" "oder" "aber" "nur" "gerade" "erst" "kurz" "auch" "noch"))
                        (member conj '("damit" "während" "bevor" "nachdem")))
              (push (list (match-beginning 2) (match-end 2)
                          (format "Komma vor %s (Nebensatz)" (well-formed-quote conj))
                          (list ", "))
                    out)))
          (setq pos (match-end 2))))
      (nreverse out))))

(well-formed-define-rule typography
  :category 'correctness :level 'info
  :doc "Typography: a hyphen used as a dash (word - word), three dots for an
ellipsis, an x for a multiplication sign between numbers."
  :examples '(("this - and that" . "this – and that") ("wait..." . "wait…") ("1920x1080" . "1920×1080"))
  :function
  (lambda (para)
    (funcall (well-formed-regexps
              `(("[[:alpha:]]\\( - \\)[[:alpha:]]" "A hyphen as a dash: an en dash (–) or em dash (—)?"
                 ,(if (equal (well-formed-para-lang para) "de") " – " " – ") 1)
                ("[[:alpha:]]\\(\\.\\.\\.\\)" "Three dots: the ellipsis character (…)?" "…" 1)
                ("[0-9]\\(x\\)[0-9]" "Multiplication sign (×)?" "×" 1 t)))
             para)))

(well-formed-define-rule vague-this
  :category 'clarity :level 'info
  :doc "A sentence opening with a bare \"This\" or \"It\" + verb leaves the
reader to guess what it points at: \"This shows\" what?  Name it: \"This
result shows\"."
  :examples '(("This means we wait." . "This delay means we wait."))
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) out (case-fold-search nil) (i 0))
      (pcase-dolist (`(,b . ,_e) (well-formed-para-sentences para))
        (when (and (> i 0)
                   (eql b (string-match (if (equal (well-formed-para-lang para) "de")
                                            "\\(Dies\\|Das\\) \\(zeigt\\|bedeutet\\|führt\\|macht\\|ist\\|heißt\\)\\>"
                                          "\\(This\\|That\\) \\(shows\\|means\\|leads\\|makes\\|is\\|was\\|causes\\|allows\\|gives\\|helps\\)\\>")
                                        text b)))
          (push (list (match-beginning 1) (match-end 2)
                      (format "%s what? Name what it refers to" (well-formed-quote (match-string 1 text)))
                      nil)
                out))
        (cl-incf i))
      (nreverse out))))

;;;; Clarity

(defvar well-formed-wordy-en
  '(("in order to" . "to") ("in order for" . "for") ("so as to" . "to")
    ("due to the fact that" . "because") ("owing to the fact that" . "because")
    ("in light of the fact that" . "because") ("on the grounds that" . "because")
    ("in spite of the fact that" . "although") ("despite the fact that" . "although")
    ("regardless of the fact that" . "although") ("the fact that" . "that")
    ("at this point in time" . "now") ("at the present time" . "now") ("at this moment in time" . "now")
    ("at the current time" . "now") ("at this time" . "now") ("in this day and age" . "today")
    ("in the near future" . "soon") ("in the event that" . "if") ("in the event of" . "if")
    ("for the purpose of" . "for") ("with the exception of" . "except") ("with the result that" . "so that")
    ("is able to" . "can") ("are able to" . "can") ("was able to" . "could") ("were able to" . "could")
    ("has the ability to" . "can") ("have the ability to" . "can") ("has the capacity to" . "can")
    ("on a daily basis" . "daily") ("on a weekly basis" . "weekly") ("on a monthly basis" . "monthly")
    ("on a regular basis" . "regularly") ("in close proximity to" . "near") ("in the vicinity of" . "near")
    ("a large number of" . "many") ("a great number of" . "many") ("a small number of" . "a few")
    ("a majority of" . "most") ("the majority of" . "most") ("a significant number of" . "many")
    ("in addition to" . "besides") ("as a matter of fact" . "in fact") ("it is important to note that" . "")
    ("it should be noted that" . "") ("it is worth noting that" . "") ("it is worth mentioning that" . "")
    ("needless to say" . "") ("it goes without saying that" . "") ("there is no doubt that" . "clearly")
    ("first and foremost" . "first") ("each and every" . "every") ("until such time as" . "until")
    ("with respect to" . "about") ("with regard to" . "about") ("with reference to" . "about")
    ("in relation to" . "about") ("in connection with" . "about") ("pertaining to" . "about")
    ("make a decision" . "decide") ("made a decision" . "decided") ("come to a conclusion" . "conclude")
    ("came to a conclusion" . "concluded") ("give consideration to" . "consider")
    ("take into consideration" . "consider") ("conduct an investigation" . "investigate")
    ("perform an analysis" . "analyze") ("carry out an analysis" . "analyze") ("provide assistance" . "help")
    ("reach an agreement" . "agree") ("make an assumption" . "assume") ("make reference to" . "refer to")
    ("is indicative of" . "indicates") ("are indicative of" . "indicate") ("in a timely manner" . "promptly")
    ("at all times" . "always") ("by means of" . "by") ("along the lines of" . "like")
    ("as of yet" . "yet") ("as to whether" . "whether") ("whether or not" . "whether")
    ("has a tendency to" . "tends to") ("have a tendency to" . "tend to") ("is in need of" . "needs")
    ("are in need of" . "need") ("prior to" . "before") ("subsequent to" . "after") ("take action" . "act")
    ("a total of" . "") ("all of the" . "all the") ("both of the" . "both") ("off of" . "off")
    ("outside of" . "outside") ("inside of" . "inside") ("in spite of" . "despite")
    ("for the reason that" . "because") ("in the absence of" . "without") ("in excess of" . "more than")
    ("in the process of" . "") ("the question as to whether" . "whether") ("in terms of" . "in")
    ("it is possible that" . "perhaps") ("there is a chance that" . "perhaps") ("it is clear that" . "clearly")
    ("it is evident that" . "clearly") ("in a manner similar to" . "like") ("on two separate occasions" . "twice")
    ("during the course of" . "during") ("in the course of" . "during") ("for a period of" . "for")
    ("at a later date" . "later") ("at an early date" . "soon") ("in the amount of" . "for")
    ("give an indication of" . "indicate") ("make an attempt to" . "try to") ("make an effort to" . "try to")
    ("is located in" . "is in") ("are located in" . "are in") ("serves the function of" . "is")
    ("on behalf of" . "for") ("in accordance with" . "by") ("is dependent upon" . "depends on")
    ("is dependent on" . "depends on") ("are dependent on" . "depend on") ("has an impact on" . "affects")
    ("have an impact on" . "affect") ("is aware of the fact that" . "knows") ("in many cases" . "often")
    ("in some cases" . "sometimes") ("in most cases" . "usually") ("on the occasion of" . "when"))
  "Wordy English phrases: (PHRASE . SHORTER), \"\" when it can go.")

(defvar well-formed-wordy-de
  '(("zur Anwendung bringen" . "anwenden") ("zur Anwendung kommen" . "angewendet werden")
    ("in Erwägung ziehen" . "erwägen") ("zur Durchführung bringen" . "durchführen")
    ("eine Entscheidung treffen" . "entscheiden") ("zum Abschluss bringen" . "abschließen")
    ("unter Beweis stellen" . "beweisen") ("in Kenntnis setzen" . "informieren")
    ("Verwendung finden" . "verwendet werden") ("Bezug nehmen auf" . "sich beziehen auf")
    ("eine Analyse durchführen" . "analysieren") ("Berücksichtigung finden" . "berücksichtigt werden")
    ("eine Prüfung vornehmen" . "prüfen") ("zur Verfügung stellen" . "bereitstellen")
    ("in Anbetracht der Tatsache, dass" . "da") ("aufgrund der Tatsache, dass" . "weil")
    ("trotz der Tatsache, dass" . "obwohl") ("die Tatsache, dass" . "dass") ("zum jetzigen Zeitpunkt" . "jetzt")
    ("zum gegenwärtigen Zeitpunkt" . "jetzt") ("zu diesem Zeitpunkt" . "dann") ("in der Lage sein" . "können")
    ("ist in der Lage" . "kann") ("sind in der Lage" . "können") ("im Rahmen von" . "bei")
    ("im Rahmen der" . "bei der") ("im Hinblick auf" . "für") ("in Bezug auf" . "zu")
    ("mit Hilfe von" . "mit") ("mithilfe von" . "mit") ("zum Zwecke der" . "zur") ("des Weiteren" . "außerdem")
    ("nichtsdestotrotz" . "trotzdem") ("Fragestellung" . "Frage") ("Problemstellung" . "Problem")
    ("Zielsetzung" . "Ziel") ("Themenstellung" . "Thema") ("Aufgabenstellung" . "Aufgabe")
    ("zum Ausdruck bringen" . "ausdrücken") ("in Augenschein nehmen" . "ansehen")
    ("eine Rolle spielen" . "zählen") ("es ist zu beachten, dass" . "") ("es sei darauf hingewiesen, dass" . "")
    ("an dieser Stelle" . "hier") ("einen Beitrag leisten" . "beitragen") ("eine Erklärung abgeben" . "erklären"))
  "Wordy German phrases (Nominalstil, Füllphrasen): (PHRASE . SHORTER).")

(well-formed-define-rule wordy
  :category 'clarity :level 'warning
  :doc "Phrases that say in several words what one says: \"in order to\" is
\"to\", \"due to the fact that\" is \"because\"; in German the
Nominalstil (\"zur Anwendung bringen\" is \"anwenden\")."
  :examples '(("in order to start" . "to start") ("due to the fact that it failed" . "because it failed")
              ("eine Entscheidung treffen" . "entscheiden"))
  :function
  (let (en de)
    (lambda (para)
      (if (equal (well-formed-para-lang para) "de")
          (funcall (or de (setq de (well-formed-phrases well-formed-wordy-de "Kürzer: %s → %s"))) para)
        (funcall (or en (setq en (well-formed-phrases well-formed-wordy-en "Wordy: %s → %s")))
                 para)))))

(defvar well-formed-redundant-en
  '(("added bonus" . "bonus") ("advance planning" . "planning") ("advance warning" . "warning")
    ("past history" . "history") ("end result" . "result") ("final outcome" . "outcome")
    ("free gift" . "gift") ("true facts" . "facts") ("unexpected surprise" . "surprise")
    ("close proximity" . "proximity") ("completely finished" . "finished") ("completely eliminate" . "eliminate")
    ("absolutely essential" . "essential") ("basic fundamentals" . "fundamentals")
    ("collaborate together" . "collaborate") ("combine together" . "combine") ("join together" . "join")
    ("merge together" . "merge") ("repeat again" . "repeat") ("revert back" . "revert")
    ("return back" . "return") ("refer back" . "refer") ("reply back" . "reply") ("plan ahead" . "plan")
    ("new innovation" . "innovation") ("past experience" . "experience") ("future plans" . "plans")
    ("general consensus" . "consensus") ("consensus of opinion" . "consensus") ("ATM machine" . "ATM")
    ("PIN number" . "PIN") ("LCD display" . "LCD") ("HIV virus" . "HIV") ("RAM memory" . "RAM")
    ("ISBN number" . "ISBN") ("sum total" . "total") ("exact same" . "same") ("still remains" . "remains")
    ("summarize briefly" . "summarize") ("mutual cooperation" . "cooperation") ("postpone until later" . "postpone")
    ("first began" . "began") ("new beginning" . "beginning") ("regular routine" . "routine")
    ("unintended mistake" . "mistake") ("empty space" . "space") ("may possibly" . "may")
    ("might possibly" . "might") ("very unique" . "unique") ("really unique" . "unique") ("totally unique" . "unique")
    ("reason why" . "reason") ("over exaggerate" . "exaggerate") ("whole entire" . "entire")
    ("actual fact" . "fact") ("brief summary" . "summary") ("current status" . "status")
    ("each individual" . "each") ("enter into" . "enter") ("estimated at about" . "estimated at")
    ("foreign imports" . "imports") ("integral part" . "part") ("join up" . "join") ("joint collaboration" . "collaboration")
    ("major breakthrough" . "breakthrough") ("meet together" . "meet") ("never before" . "never")
    ("one and only" . "only") ("originally created" . "created") ("passing fad" . "fad")
    ("period of time" . "period") ("personal opinion" . "opinion") ("protest against" . "protest")
    ("raise up" . "raise") ("serious danger" . "danger") ("shuttle back and forth" . "shuttle")
    ("spell out in detail" . "spell out") ("still persists" . "persists") ("temper tantrum" . "tantrum")
    ("ten different" . "ten") ("unsolved mystery" . "mystery") ("usual custom" . "custom")
    ("visible to the eye" . "visible") ("warn in advance" . "warn") ("written down" . "written"))
  "Redundant English pairs: (PHRASE . ENOUGH).")

(defvar well-formed-redundant-de
  '(("bereits schon" . "bereits") ("schon bereits" . "schon") ("nochmals wiederholen" . "wiederholen")
    ("zurück erstatten" . "erstatten") ("zurückerstatten" . "erstatten") ("neu renoviert" . "renoviert")
    ("zusammen addieren" . "addieren") ("voll und ganz" . "ganz") ("weißer Schimmel" . "Schimmel")
    ("LCD-Display" . "LCD") ("PIN-Nummer" . "PIN") ("ISBN-Nummer" . "ISBN") ("HIV-Virus" . "HIV")
    ("ABM-Maßnahme" . "ABM") ("persönlich anwesend" . "anwesend") ("gegenseitig zusammenarbeiten" . "zusammenarbeiten")
    ("kleines Detail" . "Detail") ("absolut perfekt" . "perfekt") ("aufaddieren" . "addieren")
    ("Grundprinzip" . "Prinzip") ("Einzelindividuum" . "Individuum") ("vorprogrammiert" . "programmiert")
    ("ganz genau" . "genau") ("bisher noch nicht" . "bisher nicht") ("wieder erneut" . "erneut")
    ("erneut wieder" . "erneut") ("Rückerinnerung" . "Erinnerung") ("Zukunftsprognose" . "Prognose"))
  "Redundant German pairs (Pleonasmen): (PHRASE . ENOUGH).")

(well-formed-define-rule redundant
  :category 'clarity :level 'warning
  :doc "Words that repeat what their neighbor already says: \"end result\",
\"revert back\", \"PIN number\", \"bereits schon\"."
  :examples '(("the end result" . "the result") ("revert back" . "revert") ("bereits schon" . "bereits"))
  :function
  (let (en de)
    (lambda (para)
      (if (equal (well-formed-para-lang para) "de")
          (funcall (or de (setq de (well-formed-phrases well-formed-redundant-de "Doppelt gemoppelt: %s → %s"))) para)
        (funcall (or en (setq en (well-formed-phrases well-formed-redundant-en "Redundant: %s → %s"))) para)))))

(defvar well-formed-complex-en
  '(("utilize" . "use") ("utilizes" . "uses") ("utilized" . "used") ("utilizing" . "using") ("utilization" . "use")
    ("commence" . "begin") ("commenced" . "began") ("terminate" . "end") ("terminated" . "ended")
    ("endeavor" . "try") ("endeavour" . "try") ("facilitate" . "help") ("facilitates" . "helps")
    ("ascertain" . "find out") ("approximately" . "about") ("demonstrate" . "show") ("demonstrates" . "shows")
    ("sufficient" . "enough") ("numerous" . "many") ("purchase" . "buy") ("purchased" . "bought")
    ("assist" . "help") ("assistance" . "help") ("subsequently" . "later") ("obtain" . "get")
    ("obtained" . "got") ("individuals" . "people") ("methodology" . "method") ("modification" . "change")
    ("modifications" . "changes") ("remainder" . "rest") ("initiate" . "start") ("initiated" . "started")
    ("inquire" . "ask") ("enquire" . "ask") ("expedite" . "speed up") ("in lieu of" . "instead of")
    ("henceforth" . "from now on") ("heretofore" . "until now") ("notwithstanding" . "despite")
    ("aforementioned" . "this") ("necessitate" . "require") ("optimal" . "best") ("leverage" . "use")
    ("functionality" . "function") ("disseminate" . "spread") ("cognizant" . "aware")
    ("ameliorate" . "improve") ("elucidate" . "explain") ("promulgate" . "announce"))
  "Long words with plain equivalents: (WORD . PLAIN).")

(well-formed-define-rule complex-word
  :category 'clarity :level 'info :langs '("en")
  :doc "A plainer word says the same: use, not utilize; begin, not commence."
  :examples '(("utilize" . "use") ("approximately ten" . "about ten"))
  :function
  (let (fn)
    (lambda (para)
      (funcall (or fn (setq fn (well-formed-phrases well-formed-complex-en "Plainer: %s → %s"))) para))))

(defun well-formed--sentence-limit (para)
  (let ((limit (or (plist-get (well-formed-para-style para) :sentence) 30)))
    (if (equal (well-formed-para-lang para) "de") (round (* limit 1.15)) limit)))

(defconst well-formed--split-points
  '(("en" ("; " . "") (", and " . "") (", but " . "But ") (", so " . "So ") (", yet " . "Yet ")
          (" – " . "") (" — " . "") (", while " . "Meanwhile, ") (", whereas " . "In contrast, ")
          (", because " . "That is because ") (", which means " . "This means "))
    ("de" ("; " . "") (", und " . "") (", aber " . "Aber ") (", denn " . "Denn ") (", sondern " . "Vielmehr ")
          (" – " . "") (", weshalb " . "Deshalb ") (", wobei " . "Dabei ") (", doch " . "Doch ")))
  "Where a sentence can be cut in two: (LINK . WHAT THE SECOND SENTENCE
STARTS WITH).")

(defun well-formed--splits (para b e)
  "Ways to cut PARA's sentence B..E in two at a clause boundary, the most
balanced first: fixes (:edit LABEL RB RE STRING), offsets from B.  Each
half keeps at least five words; masked markup is never touched."
  (let* ((text (well-formed-para-text para))
         (total (well-formed--word-count text b e))
         (case-fold-search nil) out)
    (pcase-dolist (`(,link . ,start) (alist-get (well-formed-para-lang para) well-formed--split-points nil nil #'equal))
      (let ((pos b))
        (while (and (setq pos (string-search link text pos)) (< pos e))
          (let* ((after (+ pos (length link)))
                 (left (well-formed--word-count text b pos)))
            (when (and (>= left 5) (>= (- total left) 5)
                       (< after e)
                       (string-match-p "[[:alpha:]]" (string (aref text after))))
              (let* ((next (string (aref text after)))
                     (first (if (string-empty-p start) (upcase next) (concat start next)))
                     (label (format "Split: …%s. %s…"
                                    (string-trim (substring text (max b (- pos 24)) pos))
                                    (string-trim (concat first (substring text (1+ after) (min e (+ after 20))))))))
                (push (list (abs (- left (/ total 2.0)))
                            (list :edit (replace-regexp-in-string "\0" "" label)
                                  (- pos b) (1+ (- after b)) (concat ". " first)))
                      out)))
            (setq pos after)))))
    (mapcar #'cadr (seq-take (sort out (lambda (x y) (< (car x) (car y)))) 3))))

(well-formed-define-rule long-sentence
  :category 'clarity :level 'warning
  :doc "A sentence over the style's limit (general 30 words, business 25,
academic 40; German a little more).  Split it where its ideas split."
  :function
  (lambda (para)
    (let ((limit (well-formed--sentence-limit para)) (text (well-formed-para-text para)) out)
      (unless (or (zerop limit) (eq (well-formed-para-kind para) 'heading))
        (pcase-dolist (`(,b . ,e) (well-formed-para-sentences para))
          (let ((n (well-formed--word-count text b e)))
            (when (> n limit)
              (push (list b e (format "%s sentence: %d words (limit %d); split it?"
                                      (if (> n (* 1.5 limit)) "Very long" "Long") n limit)
                          (well-formed--splits para b e))
                    out)))))
      (nreverse out))))

(defun well-formed--flesch (words sentences syllables lang)
  (let ((asl (/ (float words) (max 1 sentences)))
        (asw (/ (float syllables) (max 1 words))))
    (if (equal lang "de")
        (- 180 asl (* 58.5 asw))
      (- 206.835 (* 1.015 asl) (* 84.6 asw)))))

(well-formed-define-rule hard-sentence
  :category 'clarity :level 'info
  :doc "A sentence hard to read (Flesch reading ease below 25: long words
and many of them; Amstad's version for German)."
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) out)
      (unless (eq (well-formed-para-kind para) 'heading)
        (pcase-dolist (`(,b . ,e) (well-formed-para-sentences para))
          (let* ((words (well-formed--words text b e)) (n (length words)))
            (when (and (>= n 14) (or (zerop (well-formed--sentence-limit para))
                                     (<= n (well-formed--sentence-limit para))))
              (let ((score (well-formed--flesch n 1 (apply #'+ (mapcar (lambda (w) (well-formed--syllables (car w))) words))
                                                (well-formed-para-lang para))))
                (when (< score 25)
                  (push (list b e (format "Hard to read (reading ease %d): shorter words, or two sentences?" (round score))
                              (well-formed--splits para b e))
                        out)))))))
      (nreverse out))))

(defconst well-formed--irregular-participles
  (regexp-opt '("been" "born" "beaten" "become" "begun" "bent" "bitten" "blown" "broken" "brought" "built"
                "bought" "caught" "chosen" "done" "drawn" "driven" "eaten" "fallen" "fed" "felt" "fought"
                "found" "forgotten" "forgiven" "frozen" "given" "gone" "grown" "hung" "heard" "hidden" "held"
                "hit" "hurt" "kept" "known" "laid" "led" "left" "lent" "lost" "made" "meant" "met" "paid"
                "put" "read" "ridden" "run" "said" "seen" "sold" "sent" "set" "shaken" "shown" "shut" "sung"
                "spoken" "spent" "split" "spread" "stolen" "struck" "sworn" "taken" "taught" "thought"
                "thrown" "told" "torn" "understood" "won" "worn" "written")))

(defconst well-formed--past-of-participle
  '(("been" . "was") ("born" . "bore") ("beaten" . "beat") ("begun" . "began") ("bitten" . "bit")
    ("blown" . "blew") ("broken" . "broke") ("chosen" . "chose") ("done" . "did") ("drawn" . "drew")
    ("driven" . "drove") ("eaten" . "ate") ("fallen" . "fell") ("forgotten" . "forgot")
    ("forgiven" . "forgave") ("frozen" . "froze") ("given" . "gave") ("gone" . "went") ("grown" . "grew")
    ("hidden" . "hid") ("known" . "knew") ("ridden" . "rode") ("run" . "ran") ("seen" . "saw")
    ("shaken" . "shook") ("shown" . "showed") ("spoken" . "spoke") ("stolen" . "stole") ("sworn" . "swore")
    ("taken" . "took") ("thrown" . "threw") ("torn" . "tore") ("worn" . "wore") ("written" . "wrote")
    ("won" . "won"))
  "Participles whose simple past differs; the rest (built, told, -ed) are the same.")

(defconst well-formed--agent-pronouns
  '(("me" . "I") ("him" . "he") ("her" . "she") ("us" . "we") ("them" . "they") ("you" . "you") ("it" . "it")))

(defun well-formed--active (para s-beg s-end vb ve pb pe)
  "The active form of a past passive with its actor, as a fix:
\"The file was deleted by the script\" → \"The script deleted the file\".
VB..VE is was/were, PB..PE the participle, in PARA's sentence S-BEG..S-END.
Returns (CLAUSE-BEG CLAUSE-END FIX) or nil when it isn't that simple."
  (let* ((text (well-formed-para-text para))
         (case-fold-search nil)
         (be (downcase (substring text vb ve))))
    (when (member be '("was" "were"))
      (let* ((clause-beg (let ((i vb))
                           (while (and (> i s-beg) (not (memq (aref text (1- i)) '(?, ?\; ?:)))) (setq i (1- i)))
                           (or (string-match "[^[:space:]]" text i) i)))
             (subject (string-trim (substring text clause-beg vb)))
             (by (and (eql pe (string-match "\\([^.,;:!?\0]*?\\) ?\\<by \\([^.,;:!?\0]+?\\)\\(?: \\(?:and\\|but\\|or\\|when\\|while\\|because\\|after\\|before\\|so\\)\\>\\|[.,;:!?]\\|\\'\\)" text pe))
                      (<= (match-end 0) s-end)
                      (list (string-trim (match-string 1 text)) (string-trim (match-string 2 text))
                            (match-end 2)))))
        (when (and by (not (string-empty-p subject))
                   (not (string-search "\0" (substring text clause-beg (nth 2 by))))
                   (<= (length (split-string subject)) 8)
                   (<= (length (split-string (nth 1 by))) 6))
          (pcase-let* ((`(,middle ,agent ,end) by)
                       (participle (downcase (substring text pb pe)))
                       (past (or (cdr (assoc participle well-formed--past-of-participle)) participle))
                       (starts (= clause-beg s-beg))
                       (agent (or (cdr (assoc (downcase agent) well-formed--agent-pronouns)) agent))
                       (agent (if starts (concat (upcase (substring agent 0 1)) (substring agent 1)) agent))
                       (subject (if (and starts (string-match-p "\\`\\(?:The\\|A\\|An\\|This\\|That\\|These\\|Those\\|Our\\|My\\|Your\\|His\\|Her\\|Its\\|Their\\|Every\\|Each\\|Some\\|Many\\|Most\\|All\\)\\>" subject))
                                    (concat (downcase (substring subject 0 1)) (substring subject 1))
                                  subject))
                       (active (string-join (delq nil (list agent past subject
                                                            (unless (string-empty-p middle) middle)))
                                            " ")))
            (list clause-beg end
                  (list :edit (format "Active: %s" active) 0 (- end clause-beg) active))))))))

(well-formed-define-rule passive
  :category 'clarity :level 'info
  :doc "Passive voice hides who acts.  \"The bug was fixed\" by whom?
Active: \"Anna fixed the bug.\"  Fine when the actor doesn't matter
(academic and technical styles only mention it)."
  :examples '(("The file was deleted by the script." . "The script deleted the file."))
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) (pos 0) out (case-fold-search t)
          (re (if (equal (well-formed-para-lang para) "de")
                  "\\<\\(wird\\|werden\\|wurde\\|wurden\\|worden\\)\\>[^.!?;]\\{0,60\\}?\\<\\(ge[[:alpha:]]+\\(?:t\\|en\\)\\|[[:alpha:]]+iert\\)\\>"
                (concat "\\<\\(am\\|is\\|are\\|was\\|were\\|be\\|been\\|being\\|is not\\|was not\\|isn't\\|wasn't\\|aren't\\|weren't\\)[ \t\n]+\\(?:[[:alpha:]]+ly[ \t\n]+\\)?\\("
                        "[[:alpha:]]+ed\\|" well-formed--irregular-participles "\\)\\>"))))
      (with-syntax-table well-formed--syntax-table
        (while (string-match re text pos)
          (let ((verb (downcase (match-string 2 text))))
            (unless (member verb '("interested" "tired" "excited" "used" "supposed" "based" "concerned" "involved"
                                   "pleased" "bored" "worried" "married" "related" "required" "located" "needed"
                                   "allowed" "advanced" "detailed" "experienced" "qualified" "talented" "red" "bed"
                                   "need" "seed" "speed" "feed" "shed" "embed" "indeed" "exceed" "proceed" "succeed"
                                   "gesagt" "genug" "gerade" "gestern" "gegen" "geht" "gern" "gesamt" "genau"))
              (let* ((s (cl-find-if (lambda (s) (and (<= (car s) (match-beginning 0)) (<= (match-end 0) (cdr s))))
                                    (well-formed-para-sentences para)))
                     (active (and s (equal (well-formed-para-lang para) "en")
                                  (save-match-data
                                    (well-formed--active para (car s) (cdr s) (match-beginning 1) (match-end 1)
                                                         (match-beginning 2) (match-end 2))))))
                (push (if active
                          (list (nth 0 active) (nth 1 active) "Passive voice: active is clearer" (list (nth 2 active)))
                        (list (match-beginning 0) (match-end 0)
                              (if (equal (well-formed-para-lang para) "de")
                                  "Passiv: wer handelt? Aktiv ist oft klarer"
                                "Passive voice: who does it? Active is often clearer")
                              nil))
                      out))))
          (setq pos (match-end 0))))
      (nreverse out))))

(well-formed-define-rule double-negative
  :category 'clarity :level 'info :langs '("en")
  :doc "Two negations cancel out and slow the reader: \"not uncommon\" is
\"common\" (or \"frequent\")."
  :examples '(("not uncommon" . "common") ("don't know nothing" . "know nothing"))
  :function
  (well-formed-regexps
   '(("\\<not \\(un\\|in\\|im\\|dis\\)\\([[:alpha:]]\\{4,\\}\\)\\>" "Double negative %s: say it positively?"
      (lambda (m) (replace-regexp-in-string "\\`not \\(?:un\\|in\\|im\\|dis\\)" "" m)))
     ("\\<\\(?:don't\\|doesn't\\|didn't\\|can't\\|won't\\|isn't\\|wasn't\\|never\\)\\(?: [[:alpha:]]+\\)\\{0,2\\} \\(?:nothing\\|nobody\\|nowhere\\|none\\|no one\\)\\>"
      "Double negative: %s" nil))))

(well-formed-define-rule sentence-variety
  :category 'clarity :level 'info
  :doc "Many commas in one sentence, or a run-on held together by \"and\"."
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) out (case-fold-search t))
      (pcase-dolist (`(,b . ,e) (well-formed-para-sentences para))
        (let ((s (substring text b e)))
          (when (>= (cl-count ?, s) 6)
            (push (list b e (format "%d commas in one sentence: a list, or several sentences?" (cl-count ?, s)) nil) out))
          (let ((ands (let ((pos 0) (n 0))
                        (while (string-match "\\<\\(and\\|und\\)\\>" s pos) (setq n (1+ n) pos (match-end 0)))
                        n)))
            (when (>= ands 4)
              (push (list b e (format "\"%s\" %d times in one sentence: split it?"
                                      (if (equal (well-formed-para-lang para) "de") "und" "and") ands)
                          nil)
                    out)))))
      (nreverse out))))

;;;; Engagement

(defvar well-formed-cliches-en
  '("at the end of the day" "avoid like the plague" "think outside the box" "low-hanging fruit"
    "in the nick of time" "only time will tell" "read between the lines" "needle in a haystack"
    "tip of the iceberg" "last but not least" "better late than never" "crystal clear"
    "a perfect storm" "game changer" "game-changer" "the elephant in the room" "push the envelope"
    "back to square one" "hit the ground running" "every cloud has a silver lining" "few and far between"
    "the calm before the storm" "par for the course" "slowly but surely" "a blessing in disguise"
    "all walks of life" "as luck would have it" "fit as a fiddle" "at the drop of a hat" "cutting-edge"
    "paradigm shift" "move the needle" "win-win" "the bottom line" "level playing field" "raise the bar"
    "take it to the next level" "the best of both worlds" "think big" "when all is said and done"
    "a whole new ball game" "ahead of the curve" "on the same page" "time is money" "the writing on the wall"
    "under the radar" "the ball is in your court" "back to the drawing board" "a level of" "plain sailing")
  "English clichés.")

(defvar well-formed-cliches-de
  '("am Ende des Tages" "unterm Strich" "auf Augenhöhe" "ins Boot holen" "Nägel mit Köpfen"
    "nicht das Gelbe vom Ei" "an einem Strang ziehen" "das A und O" "last but not least"
    "im Endeffekt" "aus der Komfortzone" "zielführend" "auf den Punkt gebracht" "Fakt ist" "Hand aufs Herz"
    "in trockenen Tüchern" "am Puls der Zeit" "Win-win-Situation" "Mehrwert schaffen")
  "German Floskeln.")

(well-formed-define-rule cliche
  :category 'engagement :level 'info
  :doc "Phrases worn smooth by use: the reader skims them.  Say the thing
itself."
  :examples '(("at the end of the day, it works" . "in the end, it works"))
  :function
  (let (en de)
    (lambda (para)
      (if (equal (well-formed-para-lang para) "de")
          (funcall (or de (setq de (well-formed-phrases (mapcar #'list well-formed-cliches-de) "Floskel: %s"))) para)
        (funcall (or en (setq en (well-formed-phrases (mapcar #'list well-formed-cliches-en) "Cliché: %s"))) para)))))

(defvar well-formed-intensified-en
  '(("very good" "excellent" "great") ("very bad" "terrible" "awful") ("very big" "huge" "enormous")
    ("very large" "huge") ("very small" "tiny") ("very important" "crucial" "essential")
    ("very happy" "delighted" "thrilled") ("very sad" "miserable") ("very tired" "exhausted")
    ("very hard" "difficult" "arduous") ("very difficult" "arduous") ("very easy" "effortless")
    ("very fast" "rapid" "swift") ("very quick" "rapid") ("very slow" "sluggish") ("very old" "ancient")
    ("very clear" "obvious") ("very sure" "certain") ("very often" "frequently") ("very much" "greatly")
    ("very different" "distinct") ("very similar" "nearly identical") ("very simple" "basic")
    ("very interesting" "fascinating") ("very boring" "tedious") ("very angry" "furious")
    ("very scared" "terrified") ("very beautiful" "stunning") ("very smart" "brilliant")
    ("very rich" "wealthy") ("very poor" "destitute") ("very cold" "freezing") ("very hot" "scorching")
    ("very bright" "dazzling") ("very dark" "pitch-black") ("very loud" "deafening") ("very quiet" "hushed")
    ("very strong" "powerful") ("very weak" "feeble") ("very wrong" "mistaken") ("very useful" "invaluable")
    ("very common" "widespread") ("very rare" "scarce") ("very expensive" "costly") ("very cheap" "inexpensive")
    ("really good" "excellent") ("really bad" "terrible") ("really important" "crucial")
    ("really big" "huge") ("really small" "tiny") ("really easy" "effortless") ("really hard" "difficult")
    ("really fast" "rapid") ("really interesting" "fascinating"))
  "Intensifier + bland adjective → one stronger word.")

(well-formed-define-rule bland
  :category 'engagement :level 'info
  :doc "\"very\" plus a plain word: one precise word reads stronger
\(very important → crucial).  Bare intensifiers (very, really, extremely)
rarely add anything."
  :examples '(("a very important step" . "a crucial step"))
  :function
  (let (fn)
    (lambda (para)
      (append
       (funcall (or fn (setq fn (well-formed-phrases well-formed-intensified-en "Stronger: %s → %s"))) para)
       (when (equal (well-formed-para-lang para) "en")
         (funcall (well-formed-regexps
                   '(("\\<\\(?:very\\|really\\|extremely\\|totally\\|absolutely\\|incredibly\\|super\\) \\(?:very\\|really\\)\\>"
                      "Stacked intensifiers: %s" nil)))
                  para))))))

(defvar well-formed-overused-ignore
  '("which" "there" "their" "these" "those" "about" "would" "could" "should" "other" "where" "while"
    "being" "after" "before" "because" "every" "using" "without" "within" "between" "through" "under"
    "dieser" "diese" "dieses" "werden" "wurde" "nicht" "einer" "einem" "einen" "eines" "durch" "haben"
    "können" "seine" "ihrer" "wenn" "schon" "immer" "noch" "auch" "sind" "oder" "aber")
  "Long function words not reported as overused.")

(well-formed-define-rule overused
  :category 'engagement :level 'info
  :doc "The same word three or more times in one paragraph.  A synonym, a
pronoun, or a restructured sentence varies it (unless it's the term the
text is about, then ignore it)."
  :function
  (lambda (para)
    (unless (eq (well-formed-para-kind para) 'heading)
      (let* ((text (well-formed-para-text para))
             (words (well-formed--words text))
             (counts (make-hash-table :test #'equal))
             out)
        (when (>= (length words) 25)
          (dolist (w words)
            (let ((k (downcase (car w))))
              (when (and (>= (length k) 5) (not (member k well-formed-overused-ignore))
                         ;; names and terms (capitalized mid-sentence) are what the text is about
                         (not (and (equal (well-formed-para-lang para) "en")
                                   (let ((case-fold-search nil)) (string-match-p "\\`[[:upper:]]" (car w))))))
                (push w (gethash k counts)))))
          (maphash (lambda (k ws)
                     (when (>= (length ws) 3)
                       (let ((ws (reverse ws)))
                         ;; Once per word, at its third use.
                         (let ((w (nth 2 ws)))
                           (push (list (cadr w) (cddr w)
                                       (format "%s used %d times in this paragraph" (well-formed-quote k) (length ws))
                                       nil)
                                 out)))))
                   counts))
        out))))

(well-formed-define-rule monotonous-start
  :category 'engagement :level 'info
  :doc "Three sentences in a row starting with the same word."
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) (prev nil) (run 0) out)
      (pcase-dolist (`(,b . ,e) (well-formed-para-sentences para))
        (let* ((w (car (well-formed--words text b e))) (k (and w (downcase (car w)))))
          (if (and k (equal k prev)) (cl-incf run) (setq run 1 prev k))
          (when (and w (= run 3))
            (push (list (cadr w) (cddr w) (format "Third sentence in a row starting with %s" (well-formed-quote (car w))) nil)
                  out))))
      (nreverse out))))

(defconst well-formed--not-adverbs
  '("only" "early" "family" "apply" "reply" "supply" "july" "italy" "ugly" "holy" "daily" "weekly"
    "monthly" "yearly" "hourly" "friendly" "lonely" "lovely" "silly" "rely" "belly" "fly" "ally" "bully"
    "jelly" "rally" "tally" "assembly" "anomaly" "monopoly" "butterfly" "emily" "kelly" "billy" "lily"
    "sally" "molly" "curly" "burly" "holly" "imply" "comply" "multiply" "elderly" "costly" "likely"
    "unlikely" "orderly" "deadly" "lively" "timely" "only" "reply" "rally" "homely" "manly" "scholarly"
    "worldly" "chilly" "hilly" "bubbly" "wiggly" "jolly" "doily" "bodily" "fully"))

(well-formed-define-rule adverb
  :category 'engagement :level 'info :langs '("en")
  :doc "Three or more -ly adverbs in one sentence: a stronger verb usually
does their work (ran quickly → sprinted)."
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) out)
      (pcase-dolist (`(,b . ,e) (well-formed-para-sentences para))
        (let ((advs (cl-remove-if-not
                     (lambda (w) (let ((k (downcase (car w))))
                                   (and (string-suffix-p "ly" k) (> (length k) 4)
                                        (not (member k well-formed--not-adverbs)))))
                     (well-formed--words text b e))))
          (when (or (>= (length advs) 3)
                    (and (eq (plist-get (well-formed-para-style para) :name) 'creative) advs))
            (dolist (w advs)
              (push (list (cadr w) (cddr w) (format "Adverb %s: a stronger verb or adjective?" (well-formed-quote (car w))) (list ""))
                    out)))))
      (nreverse out))))

;;;; Delivery

(defvar well-formed-hedges-en
  '(("I think" . "") ("I believe" . "") ("I feel like" . "") ("I guess" . "") ("I suppose" . "")
    ("it seems that" . "") ("it seems like" . "") ("sort of" . "") ("kind of" . "") ("somewhat" . "")
    ("I was wondering if" . "could") ("just wanted to" . "want to") ("sorry to bother you" . "")
    ("if that makes sense" . "") ("hopefully" . "") ("a little bit" . "") ("more or less" . "")
    ("in my opinion" . "") ("to be honest" . "") ("I might be wrong" . "") ("not sure if" . "")
    ("maybe" . "") ("perhaps" . "") ("possibly" . "") ("arguably" . ""))
  "Phrases that make a writer sound unsure.")

(defvar well-formed-hedges-de
  '(("ich denke" . "") ("ich glaube" . "") ("eigentlich" . "") ("irgendwie" . "") ("quasi" . "")
    ("sozusagen" . "") ("gewissermaßen" . "") ("halt" . "") ("ziemlich" . "") ("eher" . "")
    ("vielleicht" . "") ("möglicherweise" . "") ("wohl" . "") ("an sich" . "") ("im Grunde" . "")
    ("meines Erachtens" . "") ("ein bisschen" . "") ("einigermaßen" . "") ("in gewisser Weise" . ""))
  "Füllwörter und Weichmacher.")

(well-formed-define-rule hedge
  :category 'delivery :level 'info
  :doc "Hedges make a statement sound unsure; one per text may be honest,
several sound like you don't believe yourself.  German: Füllwörter."
  :examples '(("I think we should ship it" . "We should ship it") ("Das ist eigentlich gut" . "Das ist gut"))
  :function
  (let (en de)
    (lambda (para)
      (if (equal (well-formed-para-lang para) "de")
          (funcall (or de (setq de (well-formed-phrases well-formed-hedges-de "Füllwort/Weichmacher: %s"))) para)
        (funcall (or en (setq en (well-formed-phrases well-formed-hedges-en "Sounds unsure: %s"))) para)))))

(defvar well-formed-informal-en
  '(("gonna" . "going to") ("wanna" . "want to") ("gotta" . "have to") ("kinda" . "kind of")
    ("sorta" . "sort of") ("yeah" . "yes") ("yep" . "yes") ("nope" . "no") ("ok" . "acceptable")
    ("okay" . "acceptable") ("stuff" . "things") ("guys" . "everyone") ("awesome" . "excellent")
    ("cool" . "good") ("tons of" . "many") ("lots of" . "many") ("a lot of" . "many") ("a bunch of" . "several")
    ("pretty good" . "good") ("pretty much" . "almost") ("btw" . "by the way") ("fyi" . "for your information")
    ("lol" . "") ("imo" . "in my opinion") ("asap" . "as soon as possible") ("thru" . "through")
    ("tho" . "though") ("cuz" . "because") ("'cause" . "because") ("get rid of" . "remove")
    ("figure out" . "determine") ("check out" . "examine") ("a couple of" . "two") ("kids" . "children")
    ("dumb" . "unwise") ("crazy" . "extraordinary") ("super" . "very"))
  "Informal words, with the formal register's word.")

(well-formed-define-rule informal
  :category 'delivery :level 'info :langs '("en")
  :doc "Informal for a formal text (academic, business): gonna, a lot of,
stuff.  Off in the casual and creative styles."
  :function
  (let (fn)
    (lambda (para)
      (when (memq (plist-get (well-formed-para-style para) :name) '(academic business technical))
        (funcall (or fn (setq fn (well-formed-phrases well-formed-informal-en "Informal: %s → %s"))) para)))))

(defvar well-formed-contractions
  '(("don't" . "do not") ("can't" . "cannot") ("won't" . "will not") ("isn't" . "is not")
    ("aren't" . "are not") ("wasn't" . "was not") ("weren't" . "were not") ("hasn't" . "has not")
    ("haven't" . "have not") ("hadn't" . "had not") ("doesn't" . "does not") ("didn't" . "did not")
    ("shouldn't" . "should not") ("wouldn't" . "would not") ("couldn't" . "could not") ("mustn't" . "must not")
    ("I'm" . "I am") ("you're" . "you are") ("we're" . "we are") ("they're" . "they are") ("I've" . "I have")
    ("you've" . "you have") ("we've" . "we have") ("they've" . "they have") ("I'll" . "I will")
    ("you'll" . "you will") ("we'll" . "we will") ("they'll" . "they will") ("it's" . "it is")
    ("that's" . "that is") ("there's" . "there is") ("what's" . "what is") ("let's" . "let us")
    ("he's" . "he is") ("she's" . "she is") ("who's" . "who is") ("I'd" . "I would") ("we'd" . "we would")))

(well-formed-define-rule contraction
  :category 'delivery :level 'info :langs '("en")
  :doc "Contractions read as spoken English; formal writing (academic, and a
little in business) spells them out."
  :function
  (let (fn)
    (lambda (para)
      (funcall (or fn (setq fn (well-formed-phrases
                                (append well-formed-contractions
                                        (mapcar (lambda (e) (cons (string-replace "'" "’" (car e)) (cdr e)))
                                                well-formed-contractions))
                                "Contraction in formal writing: %s → %s")))
               para))))

(defvar well-formed-jargon-en
  '(("synergy" . "cooperation") ("synergies" . "benefits") ("leverage" . "use") ("leveraging" . "using")
    ("circle back" . "return to") ("touch base" . "talk") ("going forward" . "from now on")
    ("best-in-class" . "best") ("value-add" . "benefit") ("deep dive" . "close look")
    ("bandwidth" . "time") ("action item" . "task") ("ideate" . "brainstorm") ("impactful" . "effective")
    ("actionable" . "practical") ("learnings" . "lessons") ("onboarding" . "introduction")
    ("operationalize" . "carry out") ("incentivize" . "encourage") ("socialize" . "share")
    ("utilize" . "use") ("holistic" . "complete") ("robust" . "strong") ("seamless" . "smooth")
    ("empower" . "enable") ("streamline" . "simplify") ("core competency" . "strength")
    ("thought leader" . "expert") ("drill down" . "examine") ("pain point" . "problem")
    ("mission-critical" . "essential") ("ecosystem" . "system"))
  "Business jargon and buzzwords.")

(well-formed-define-rule jargon
  :category 'delivery :level 'info :langs '("en")
  :doc "Corporate buzzwords: they sound like everyone else and say little."
  :function
  (let (fn)
    (lambda (para)
      (unless (memq (plist-get (well-formed-para-style para) :name) '(casual creative))
        (funcall (or fn (setq fn (well-formed-phrases well-formed-jargon-en "Jargon: %s → %s"))) para)))))

(defvar well-formed-inclusive
  '(("guys" . ("everyone" "folks" "all")) ("you guys" . ("you all" "everyone"))
    ("manpower" . ("workforce" "staff")) ("mankind" . ("humankind" "humanity"))
    ("chairman" . ("chair" "chairperson")) ("whitelist" . ("allowlist")) ("blacklist" . ("denylist" "blocklist"))
    ("whitelisted" . ("allowed")) ("blacklisted" . ("blocked")) ("master/slave" . ("primary/replica"))
    ("sanity check" . ("quick check" "smoke test")) ("dummy value" . ("placeholder"))
    ("he or she" . ("they")) ("his or her" . ("their")) ("him or her" . ("them")) ("he/she" . ("they"))
    ("policeman" . ("police officer")) ("fireman" . ("firefighter")) ("stewardess" . ("flight attendant"))
    ("man-hours" . ("person-hours")) ("grandfathered" . ("legacy")) ("man-made" . ("artificial"))
    ("businessman" . ("businessperson")) ("crippled" . ("disabled")) ("lame" . ("weak")))
  "Exclusionary terms with alternatives.")

(well-formed-define-rule inclusive
  :category 'delivery :level 'info :langs '("en")
  :doc "Words that leave people out: gendered defaults (he or she, manpower)
and terms with a history (master/slave, blacklist)."
  :function
  (let (fn)
    (lambda (para)
      (funcall (or fn (setq fn (well-formed-phrases well-formed-inclusive "Inclusive: %s → %s"))) para))))

(well-formed-define-rule weasel
  :category 'delivery :level 'info
  :doc "Claims without a source: \"studies show\", \"many people say\",
\"Experten sagen\".  Name the study, the people."
  :function
  (let (en de)
    (lambda (para)
      (if (equal (well-formed-para-lang para) "de")
          (funcall (or de (setq de (well-formed-phrases
                                    (mapcar #'list '("Studien zeigen" "Experten sagen" "Experten sind sich einig"
                                                     "man sagt" "es heißt" "viele Leute" "viele Menschen glauben"
                                                     "bekanntlich" "es ist allgemein bekannt"))
                                    "Ohne Quelle: %s – wer genau?")))
                   para)
        (funcall (or en (setq en (well-formed-phrases
                                  (mapcar #'list '("studies show" "studies have shown" "research shows"
                                                   "research has shown" "experts agree" "experts say" "many people say"
                                                   "some people say" "some say" "it is said" "it is believed"
                                                   "it is widely believed" "it is known" "it has been suggested"
                                                   "many believe" "critics say" "scientists say" "everyone knows"))
                                  "Unsourced claim: %s (who?)")))
                 para)))))

(well-formed-define-rule first-person
  :category 'delivery :level 'info :langs '("en")
  :doc "First person singular in academic writing (many fields prefer \"we\"
or an impersonal phrasing)."
  :function
  (lambda (para)
    (when (eq (plist-get (well-formed-para-style para) :name) 'academic)
      (funcall (well-formed-regexps '(("\\<\\(I\\|me\\|my\\|mine\\)\\>" "First person %s in academic prose" nil 0 t)))
               para))))

(well-formed-define-rule conjunction-start
  :category 'delivery :level 'info :langs '("en")
  :doc "Formal prose rarely starts a sentence with And, But, So, Or."
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) out (case-fold-search nil))
      (pcase-dolist (`(,b . ,_e) (well-formed-para-sentences para))
        (when (and (eql b (string-match "\\(And\\|But\\|So\\|Or\\|Also\\)\\>" text b)))
          (let* ((conj (match-string 1 text)) (me (match-end 0))
                 (next (and (< (1+ me) (length text)) (eq (aref text me) ?\s) (aref text (1+ me)))))
            (push (list b me (format "Sentence starts with %s" (well-formed-quote conj))
                        (when (and next (memq (get-char-code-property next (quote general-category)) (quote (Ll Lu))))
                          (list (list :edit (format "Drop %s" (well-formed-quote conj)) 0 (+ 2 (- me b))
                                      (upcase (string next))))))
                  out))))
      (nreverse out))))

(well-formed-define-rule shouting
  :category 'delivery :level 'info
  :doc "Words in capitals (not acronyms) and exclamation marks read as
shouting."
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) (pos 0) out (case-fold-search nil))
      (with-syntax-table well-formed--syntax-table
        (while (string-match "\\<[[:upper:]]\\{6,\\}\\>" text pos)
          (unless (member (match-string 0 text) '("README" "TODO" "FIXME" "LICENSE" "UNESCO" "UNICEF" "INSERT" "NORMAL" "VISUAL" "REPLACE"
                                                    "MOTION" "OPERATOR" "CHANGELOG" "PROPERTIES" "DEADLINE" "SCHEDULED"))
            (push (list (match-beginning 0) (match-end 0) (format "%s in capitals reads as shouting"
                                                                  (well-formed-quote (match-string 0 text)))
                        (list (downcase (match-string 0 text))))
                  out))
          (setq pos (match-end 0))))
      (let ((n (cl-count ?! text)))
        (when (>= n 3)
          (push (list (string-search "!" text) (1+ (string-search "!" text))
                      (format "%d exclamation marks in one paragraph" n) nil)
                out)))
      (nreverse out))))

(well-formed-define-rule negative
  :category 'delivery :level 'info :langs '("en")
  :doc "Negative framing where a positive one says the same (business):
\"don't forget\" is \"remember\", \"not possible\" is \"impossible\"
or better what is possible."
  :examples '(("Don't forget to save." . "Remember to save."))
  :function
  (let (fn)
    (lambda (para)
      (when (eq (plist-get (well-formed-para-style para) :name) 'business)
        (funcall (or fn (setq fn (well-formed-phrases
                                  '(("don't forget" . "remember") ("do not forget" . "remember")
                                    ("not possible" . "impossible") ("not able to" . "unable to")
                                    ("not many" . "few") ("not the same" . "different") ("did not remember" . "forgot")
                                    ("not unless" . "only if") ("unfortunately" . "") ("we regret" . "")
                                    ("failed to" . "did not") ("you must" . "please") ("you failed" . "")
                                    ("problem" . "issue") ("no problem" . "glad to help"))
                                  "Positive framing: %s → %s")))
                 para)))))

(well-formed-define-rule fragment
  :category 'correctness :level 'warning :langs '("en")
  :doc "A clause that leans on another (because, although, which …) standing
alone as a sentence: join it to the one before, or finish it."
  :examples '(("We left early. Because it rained." . "We left early because it rained."))
  :function
  (lambda (para)
    (let ((text (well-formed-para-text para)) out (case-fold-search nil) prev-end word)
      (pcase-dolist (`(,b . ,e) (well-formed-para-sentences para))
        (let ((s (string-trim-right (substring text b e))))
          (when (and (string-match "\\`\\(Because\\|Although\\|Though\\|Whereas\\|Which\\|Unless\\|Whenever\\) [[:alpha:]]" s)
                     (setq word (match-string 1 s))
                     (not (string-search "," s))
                     (string-suffix-p "." s)
                     (>= (length (split-string s)) 3))
            (let* ((msg (format "Fragment: a %s clause on its own" (well-formed-quote (downcase word))))
                   (before (and prev-end (string-trim-right (substring text 0 prev-end))))
                   (period (and before (string-suffix-p "." before) (1- (length before)))))
              (push (if period
                        ;; Joined to the sentence before: from its period on.
                        (list period (+ b (length s)) msg
                              (list (concat " " (downcase (substring s 0 1)) (substring s 1))))
                      (list b (+ b (length s)) msg nil))
                    out)))
          (setq prev-end e)))
      (nreverse out))))

(well-formed-define-rule run-on
  :category 'correctness :level 'warning :langs '("en")
  :doc "Two sentences run together: a capitalized pronoun in mid-sentence
usually starts a new one whose period went missing."
  :examples '(("We left early We were tired." . "We left early. We were tired."))
  :function
  (well-formed-regexps
   '(("[[:lower:]]\\( \\)\\(?:We\\|They\\|He\\|She\\|It\\|You\\) \\(?:am\\|is\\|are\\|was\\|were\\|have\\|has\\|had\\|will\\|can\\|could\\|would\\|should\\|did\\|do\\|does\\)\\>"
      "Run-on: a new sentence seems to start here" ". " 1 t))))

(well-formed-define-rule rhythm
  :category 'engagement :level 'info
  :doc "Four or more sentences in a row of about the same length read as a
drone; vary them (a short one lands)."
  :function
  (lambda (para)
    (let* ((text (well-formed-para-text para))
           (lens (mapcar (pcase-lambda (`(,b . ,e)) (list b e (well-formed--word-count text b e)))
                         (well-formed-para-sentences para)))
           out run)
      (cl-flet ((flush ()
                  (when (>= (length run) 4)
                    (let ((r (reverse run)))
                      (push (list (car (car r)) (cadr (car (last r)))
                                  (format "%d sentences of about %d words in a row: vary the length"
                                          (length r) (round (/ (cl-loop for x in r sum (nth 2 x)) (float (length r))))))
                            out)))
                  (setq run nil)))
        (dolist (s lens)
          (if (and run (>= (nth 2 s) 6)
                   (<= (abs (- (nth 2 s) (nth 2 (car (last run))))) 3)
                   (<= (abs (- (nth 2 s) (nth 2 (car run)))) 3))
              (push s run)
            (flush)
            (when (>= (nth 2 s) 6) (setq run (list s)))))
        (flush))
      (nreverse out))))

(defconst well-formed--past-verb
  "\\`\\(?:was\\|were\\|had\\|did\\|went\\|came\\|said\\|made\\|took\\|got\\|saw\\|knew\\|thought\\|found\\|gave\\|told\\|felt\\|left\\|ran\\|wrote\\|[[:alpha:]]+ed\\)\\'")
(defconst well-formed--present-verb
  "\\`\\(?:is\\|are\\|am\\|has\\|have\\|does\\|do\\|goes\\|comes\\|says\\|makes\\|takes\\|gets\\|sees\\|knows\\|thinks\\|finds\\|gives\\|tells\\|feels\\|leaves\\|runs\\|writes\\|see\\|go\\|come\\|say\\|make\\|take\\|get\\|know\\|think\\|find\\|give\\|tell\\|feel\\|leave\\|run\\|write\\|want\\|need\\|walk\\|look\\)\\'")

(well-formed-define-rule tense-shift
  :category 'clarity :level 'info :langs '("en")
  :doc "A paragraph told in one tense with one sentence in another (\"We
went in. It was dark. We see a light.\"): likely a slip."
  :function
  (lambda (para)
    (let* ((text (well-formed-para-text para)) (case-fold-search nil)
           (tenses
            (cl-loop for (b . e) in (well-formed-para-sentences para)
                     for s = (substring text b e)
                     ;; The verb after a subject pronoun opening the sentence.
                     when (string-match "\\`[[:space:]]*\\(?:I\\|We\\|They\\|He\\|She\\|It\\|You\\) \\([[:alpha:]]+\\)\\>" s)
                     collect (let ((v (downcase (match-string 1 s))))
                               (list b e (cond ((string-match-p well-formed--past-verb v) 'past)
                                               ((string-match-p well-formed--present-verb v) 'present))))))
           (past (cl-count 'past tenses :key #'caddr))
           (present (cl-count 'present tenses :key #'caddr)))
      (when (and (= (min past present) 1) (>= (max past present) 3))
        (let ((odd (if (= past 1) 'past 'present)))
          (cl-loop for (b e tense) in tenses
                   when (eq tense odd)
                   collect (list b e (format "%s here; the rest of the paragraph is in the %s"
                                             (capitalize (symbol-name odd)) (if (eq odd 'past) "present" "past"))
                                 nil)))))))

(defvar well-formed-mail-modes
  '(message-mode mu4e-compose-mode notmuch-message-mode org-msg-edit-mode)
  "Modes where text is a mail to someone: politeness counts there.")

(defconst well-formed--command-verbs
  '(("en" "send" "give" "tell" "fix" "do" "make" "call" "check" "update" "provide" "let" "reply"
     "answer" "write" "add" "remove" "change" "review" "finish" "sign" "forward" "confirm"
     "explain" "share" "schedule" "book" "pay" "return" "submit" "approve" "delete" "stop")
    ("de" "schick" "schicke" "sende" "gib" "sag" "mach" "mache" "ruf" "prüf" "prüfe" "schreib"
     "schreibe" "antworte" "bestätige" "erklär" "erkläre" "teil" "teile" "lösch" "lösche" "zahl"))
  "Verbs that open a command (imperative), by language.")

(well-formed-define-rule politeness
  :category 'delivery :level 'info
  :doc "In a mail (or the business style), a bare command reads as a demand:
\"Send me the file.\" asks better as \"Please send me the file.\" or
\"Could you send me the file?\""
  :examples '(("Send me the file." . "Please send me the file."))
  :function
  (lambda (para)
    (when (or (apply #'derived-mode-p well-formed-mail-modes)
              (eq (plist-get (well-formed-para-style para) :name) 'business))
      (let* ((text (well-formed-para-text para)) (lang (well-formed-para-lang para))
             (verbs (cdr (assoc lang well-formed--command-verbs))) out)
        (pcase-dolist (`(,b . ,e) (well-formed-para-sentences para))
          (let* ((s (string-trim-right (substring text b e)))
                 (first (and (string-match "\\`\\([[:alpha:]]+\\)[[:space:]]+[[:alpha:]]" s)
                             (match-string 1 s))))
            (when (and first (member (downcase first) verbs)
                       (string-match-p "[.!]\\'" s)
                       (not (string-match-p "\\<\\(?:please\\|thanks\\|thank you\\|bitte\\|danke\\)\\>" (downcase s))))
              (let ((rest (concat (downcase (substring s 0 1)) (substring s 1 -1))))
                (push (list b (+ b (length s)) "A command in a mail: ask instead?"
                            (if (equal lang "de")
                                (list (concat "Bitte " rest "."))   ; "Könntest du" needs the verb moved
                              (list (concat "Please " rest ".") (concat "Could you " rest "?"))))
                      out)))))
        (nreverse out)))))

;;;; Consistency (whole document)

(defvar well-formed-spelling-pairs
  '(("color" . "colour") ("colors" . "colours") ("favorite" . "favourite") ("behavior" . "behaviour")
    ("behaviors" . "behaviours") ("honor" . "honour") ("labor" . "labour") ("neighbor" . "neighbour")
    ("humor" . "humour") ("flavor" . "flavour") ("center" . "centre") ("centers" . "centres")
    ("meter" . "metre") ("liter" . "litre") ("theater" . "theatre") ("fiber" . "fibre")
    ("organize" . "organise") ("organized" . "organised") ("organization" . "organisation")
    ("recognize" . "recognise") ("realize" . "realise") ("realized" . "realised") ("analyze" . "analyse")
    ("analyzed" . "analysed") ("optimize" . "optimise") ("optimized" . "optimised") ("optimization" . "optimisation")
    ("customize" . "customise") ("customized" . "customised") ("initialize" . "initialise")
    ("initialized" . "initialised") ("serialize" . "serialise") ("normalize" . "normalise")
    ("prioritize" . "prioritise") ("minimize" . "minimise") ("maximize" . "maximise") ("summarize" . "summarise")
    ("apologize" . "apologise") ("emphasize" . "emphasise") ("license" . "licence") ("defense" . "defence")
    ("offense" . "offence") ("catalog" . "catalogue") ("dialog" . "dialogue") ("analog" . "analogue")
    ("program" . "programme") ("gray" . "grey") ("traveled" . "travelled") ("traveling" . "travelling")
    ("canceled" . "cancelled") ("canceling" . "cancelling") ("modeling" . "modelling") ("labeled" . "labelled")
    ("labeling" . "labelling") ("fulfill" . "fulfil") ("enroll" . "enrol") ("judgment" . "judgement")
    ("aging" . "ageing") ("mold" . "mould") ("plow" . "plough") ("check" . "cheque") ("tire" . "tyre")
    ("aluminum" . "aluminium") ("math" . "maths") ("artifact" . "artefact"))
  "(US . UK) spellings.")

(defvar well-formed-variant-groups
  '(("email" "e-mail") ("online" "on-line") ("website" "web site") ("realtime" "real-time" "real time")
    ("open source" "open-source") ("backend" "back-end" "back end") ("frontend" "front-end" "front end")
    ("login" "log-in") ("setup" "set-up") ("filename" "file name") ("username" "user name")
    ("database" "data base") ("dataset" "data set") ("timestamp" "time stamp") ("toolchain" "tool chain")
    ("ok" "okay" "OK") ("internet" "Internet") ("web" "Web") ("co-operate" "cooperate")
    ("e.g." "e.g.,") ("i.e." "i.e.,") ("…" "...") ("percent" "per cent" "%"))
  "Spelling variants: a document should pick one.")

(defun well-formed--collect (paras regexp)
  "All matches of REGEXP in PARAS: list of (TEXT BEG END) in buffer positions."
  (let (out (case-fold-search nil))
    (dolist (p paras)
      (let ((text (well-formed-para-text p)) (pos 0) (base (well-formed-para-beg p)))
        (with-syntax-table well-formed--syntax-table
          (while (string-match regexp text pos)
            (push (list (match-string 0 text) (+ base (match-beginning 0)) (+ base (match-end 0))) out)
            (setq pos (max (1+ (match-beginning 0)) (match-end 0)))))))
    (nreverse out)))

(defun well-formed--minority (occurrences key-fn rule describe)
  "Findings for OCCURRENCES whose (KEY-FN occurrence) isn't the most frequent.
DESCRIBE gets the minority key, majority key and its count."
  (let ((counts (make-hash-table :test #'equal)))
    (dolist (o occurrences) (cl-incf (gethash (funcall key-fn o) counts 0)))
    (when (> (hash-table-count counts) 1)
      (let (major (best 0))
        (maphash (lambda (k n) (when (> n best) (setq major k best n))) counts)
        (cl-loop for o in occurrences
                 for k = (funcall key-fn o)
                 unless (equal k major)
                 collect (list (nth 1 o) (nth 2 o) rule (funcall describe k major best)
                               (list (well-formed--match-case (car o) major))))))))

(defun well-formed--consistency (paras)
  (let ((en (cl-remove-if-not (lambda (p) (equal (well-formed-para-lang p) "en")) paras))
        out)
    (when (and en (not (memq 'consistency (bound-and-true-p well-formed-disabled-categories))))
      ;; US or UK: the document's majority.
      (let* ((us (mapcar #'car well-formed-spelling-pairs)) (uk (mapcar #'cdr well-formed-spelling-pairs))
             (re (concat "\\<" (regexp-opt (append us uk) t) "\\>"))
             (occ (let ((case-fold-search t)) (well-formed--collect en re)))
             (variety (lambda (o) (if (member (downcase (car o)) us) "US" "UK"))))
        (when (cl-find "US" occ :key variety :test #'equal)
          (let ((counts (list (cl-count "US" occ :key variety :test #'equal)
                              (cl-count "UK" occ :key variety :test #'equal))))
            (when (cl-every #'cl-plusp counts)
              (let ((major (if (>= (car counts) (cadr counts)) "US" "UK")))
                (dolist (o occ)
                  (unless (equal (funcall variety o) major)
                    (let* ((w (downcase (car o)))
                           (other (if (equal major "US") (car (rassoc w well-formed-spelling-pairs))
                                    (cdr (assoc w well-formed-spelling-pairs)))))
                      (push (list (nth 1 o) (nth 2 o) 'spelling-variety
                                  (format "%s is %s; this document mostly uses %s spelling (%s)"
                                          (well-formed-quote (car o)) (if (equal major "US") "UK" "US") major other)
                                  (list (well-formed--match-case (car o) other)))
                            out)))))))))
      ;; One spelling per variant group.
      (dolist (group well-formed-variant-groups)
        (let* ((re (concat (if (string-match-p "\\`[[:alpha:]]" (car group)) "\\<" "")
                           (regexp-opt group t)
                           (if (string-match-p "[[:alpha:]]\\'" (car group)) "\\>" "")))
               (case-sensitive (cl-some (lambda (v) (not (string= v (downcase v)))) group))
               (occ (let ((case-fold-search (not case-sensitive))) (well-formed--collect en re))))
          (setq out (nconc (well-formed--minority
                            occ (lambda (o) (if case-sensitive (car o) (downcase (car o))))
                            'variant
                            (lambda (k major n) (format "%s here, %s %d× elsewhere: pick one"
                                                        (well-formed-quote k) (well-formed-quote major) n)))
                           out))))
      ;; Oxford comma: "a, b, and c" against "a, b and c".
      (let ((occ (append (mapcar (lambda (o) (cons "oxford" (cdr o)))
                                 (well-formed--collect en "\\<[[:alpha:]]+, [[:alpha:]]+\\(?: [[:alpha:]]+\\)?, \\(?:and\\|or\\) "))
                         (mapcar (lambda (o) (cons "none" (cdr o)))
                                 (well-formed--collect en "\\<[[:alpha:]]+, [[:alpha:]]+\\(?: [[:alpha:]]+\\)? \\(?:and\\|or\\) ")))))
        (setq out (nconc (well-formed--minority
                          occ #'car 'oxford-comma
                          (lambda (k _major n)
                            (if (equal k "oxford") (format "Serial comma here; %d lists elsewhere go without" n)
                              (format "No serial comma here; %d lists elsewhere have one" n))))
                         out)))
      ;; Quotes: straight against curly.
      (let ((occ (append (mapcar (lambda (o) (cons "straight" (cdr o))) (well-formed--collect paras "\"[[:alpha:]]"))
                         (mapcar (lambda (o) (cons "curly" (cdr o))) (well-formed--collect paras "[“„][[:alpha:]]")))))
        (setq out (nconc (well-formed--minority
                          occ #'car 'quote-style
                          (lambda (k major n) (format "%s quotes; %d elsewhere are %s" k n major)))
                         out))))
    (mapcar (lambda (f) (list (nth 0 f) (nth 1 f) (nth 2 f) (nth 3 f)
                              (pcase (nth 2 f)
                                ('quote-style nil)
                                ('oxford-comma
                                 ;; Toward the majority: add or drop the comma before and/or.
                                 (let ((m (buffer-substring-no-properties (nth 0 f) (nth 1 f))))
                                   (list (if (string-match-p ", \\(?:and\\|or\\) \\'" m)
                                             (replace-regexp-in-string ", \\(and\\|or\\) \\'" " \\1 " m)
                                           (replace-regexp-in-string " \\(and\\|or\\) \\'" ", \\1 " m)))))
                                (_ (nth 4 f)))))
            out)))

(well-formed-define-rule spelling-variety
  :category 'consistency :level 'warning :langs '("en")
  :doc "American and British spelling mixed in one document; the one used
more wins."
  :function #'ignore)
(well-formed-define-rule variant
  :category 'consistency :level 'info
  :doc "Two spellings of the same word in one document (email, e-mail)."
  :function #'ignore)
(well-formed-define-rule oxford-comma
  :category 'consistency :level 'info :langs '("en")
  :doc "Some lists with the serial comma (a, b, and c), some without."
  :function #'ignore)
(well-formed-define-rule quote-style
  :category 'consistency :level 'info
  :doc "Straight \"quotes\" and curly “quotes” mixed."
  :function #'ignore)

(add-hook 'well-formed-document-functions #'well-formed--consistency)

;;;; Consistency: numbers, terms, dates, headings

(defconst well-formed--number-words
  '(("2" . "two") ("3" . "three") ("4" . "four") ("5" . "five") ("6" . "six")
    ("7" . "seven") ("8" . "eight") ("9" . "nine"))
  "Small numbers, as digits and words (\"one\" is left out: it is a pronoun too).")

(defconst well-formed--units
  '("am" "pm" "px" "pt" "em" "ms" "min" "mins" "sec" "secs" "s" "h" "hrs" "kb" "mb" "gb" "tb"
    "kib" "mib" "gib" "x" "times" "percent" "cores" "bit" "bits" "fps" "hz" "ghz" "dpi" "ppi" "k")
  "Words after a number that make digits right whatever the style.")

(defconst well-formed--months
  '("January" "February" "March" "April" "May" "June" "July" "August" "September"
    "October" "November" "December"))

(defun well-formed--matches (paras regexp fn &optional case-fold)
  "Call FN with each match of REGEXP in PARAS (match data on the paragraph's
text) and the paragraph's buffer position; collect its non-nil values."
  (let (out (case-fold-search case-fold))
    (dolist (p paras)
      (let ((text (well-formed-para-text p)) (pos 0) (base (well-formed-para-beg p)))
        (with-syntax-table well-formed--syntax-table
          (while (string-match regexp text pos)
            (setq pos (max (1+ (match-beginning 0)) (match-end 0)))
            (when-let* ((v (save-match-data (funcall fn text base))))
              (push v out))))))
    (nreverse out)))

(defun well-formed--number-style (paras)
  "Small numbers as digits here, as words there: the document's majority wins.
Occurrences: (FORM BEG END KEY)."
  (let* ((digits (well-formed--matches
                  paras "\\(?:\\`\\|[^-.,:/[:alnum:]]\\)\\([2-9]\\) \\([[:lower:]]+\\)\\>"
                  (lambda (text base)
                    (unless (or (member (match-string 2 text) well-formed--units)
                                ;; Beside other numbers (6 of 8, 39-85 s): digits.
                                (string-match-p "[0-9]" (concat (substring text (max 0 (- (match-beginning 1) 30)) (match-beginning 1))
                                                                (substring text (match-end 1) (min (length text) (+ (match-end 1) 30))))))
                      (list (match-string 1 text) (+ base (match-beginning 1)) (+ base (match-end 1)) "digits")))))
         (words (well-formed--matches
                 paras (concat "\\<\\(" (regexp-opt (mapcar #'cdr well-formed--number-words)) "\\) [[:lower:]]+\\>")
                 (lambda (text base)
                   (list (match-string 1 text) (+ base (match-beginning 1)) (+ base (match-end 1)) "words"))
                 t)))
    (when (and digits words)
      (let ((major (if (>= (length digits) (length words)) "digits" "words")))
        (cl-loop for o in (if (equal major "digits") words digits)
                 for form = (car o)
                 for other = (if (equal major "digits")
                                 (car (rassoc (downcase form) well-formed--number-words))
                               (well-formed--match-case form (cdr (assoc form well-formed--number-words))))
                 collect (list (nth 1 o) (nth 2 o) 'number-style
                               (format "%s here; %d small numbers elsewhere are %s"
                                       (well-formed-quote form) (length (if (equal major "digits") digits words)) major)
                               (list other)))))))

(defun well-formed--term-case (paras)
  "A term with inner capitals (GitHub, JavaScript, macOS) written otherwise
elsewhere: the most frequent inner-capital form wins.  Paths, handles and
names (/github/x, @github, nixos-mcp) aren't the term; all lower case is only
flagged while rarer than the term (else it is likely a name: a host, a package)."
  (let ((forms (make-hash-table :test #'equal)) (case-fold-search nil))
    ;; Terms: words with an upper case letter after a lower case one.
    (dolist (o (well-formed--matches paras "\\<[[:alpha:]]*[[:lower:]][[:upper:]][[:alpha:]]*\\>"
                                     (lambda (text _) (match-string 0 text))))
      (puthash (downcase o) t forms))
    (let (out)
      (maphash
       (lambda (key _)
         (let* ((occ (well-formed--matches
                      paras (concat "\\<" (regexp-quote key) "\\>\\(?:\\'\\|[^.[:alnum:]]\\|\\.\\(?:[^[:alnum:]]\\|\\'\\)\\)")
                      (lambda (text base)
                        (let* ((b (match-beginning 0)) (e (+ b (length key))))
                          ;; The buffer's own characters: markup is masked in TEXT (/x/ is italic).
                          (unless (or (memq (char-before (+ base b)) '(?/ ?@ ?= ?~ ?- ?_))
                                      (memq (char-after (+ base e)) '(?/ ?- ?_ ?=)))
                            (list (substring text b e) (+ base b) (+ base e)))))
                      t))
                (counts (make-hash-table :test #'equal)) best (n 0))
           (dolist (o occ) (cl-incf (gethash (car o) counts 0)))
           (maphash (lambda (form c)
                      (when (and (> c n) (string-match-p "[[:lower:]][[:upper:]]" form))
                        (setq best form n c)))
                    counts)
           (when (and best (> (hash-table-count counts) 1))
             (dolist (o occ)
               (unless (or (equal (car o) best)
                           (and (equal (car o) key) (>= (gethash key counts 0) n)))
                 (push (list (nth 1 o) (nth 2 o) 'term-case
                             (format "%s: written %s %d× in this document" (well-formed-quote (car o))
                                     (well-formed-quote best) n)
                             (list best))
                       out))))))
       forms)
      out)))

(defun well-formed--parse-date (kind text)
  "(YEAR MONTH DAY) from the match data of a KIND date in TEXT, or nil."
  (let* ((g (lambda (n) (match-string n text)))
         (month-num (lambda (s) (1+ (or (cl-position s well-formed--months :test #'string=) -1))))
         (ymd (pcase kind
                ("ISO" (list (funcall g 1) (funcall g 2) (funcall g 3)))
                ("D.M.Y" (list (funcall g 3) (funcall g 2) (funcall g 1)))
                ("M/D/Y" (list (funcall g 3) (funcall g 1) (funcall g 2)))
                ("D Month Y" (list (funcall g 3) (funcall month-num (funcall g 2)) (funcall g 1)))
                ("Month D, Y" (list (funcall g 3) (funcall month-num (funcall g 1)) (funcall g 2)))))
         (n (mapcar (lambda (x) (if (stringp x) (string-to-number x) x)) ymd)))
    (pcase-let ((`(,y ,m ,d) n))
      (and (<= 1 m 12) (<= 1 d (date-days-in-month y m)) n))))

(defun well-formed--format-date (kind ymd)
  (pcase-let ((`(,y ,m ,d) ymd))
    (pcase kind
      ("ISO" (format "%04d-%02d-%02d" y m d))
      ("D.M.Y" (format "%02d.%02d.%04d" d m y))
      ("M/D/Y" (format "%d/%d/%04d" m d y))
      ("D Month Y" (format "%d %s %04d" d (nth (1- m) well-formed--months) y))
      ("Month D, Y" (format "%s %d, %04d" (nth (1- m) well-formed--months) d y)))))

(defun well-formed--date-format (paras)
  "Dates written two ways (2026-11-05, 05.11.2026, 11/5/2026, 5 November
2026, November 5, 2026): the document's majority wins."
  (let* ((month (regexp-opt well-formed--months))
         (kinds `(("ISO" . "\\<\\([12][0-9]\\{3\\}\\)-\\([01][0-9]\\)-\\([0-3][0-9]\\)\\>")
                  ("D.M.Y" . "\\<\\([0-3]?[0-9]\\)\\.\\([01]?[0-9]\\)\\.\\([12][0-9]\\{3\\}\\)\\>")
                  ("M/D/Y" . "\\<\\([01]?[0-9]\\)/\\([0-3]?[0-9]\\)/\\([12][0-9]\\{3\\}\\)\\>")
                  ("D Month Y" . ,(concat "\\<\\([0-3]?[0-9]\\)\\.? \\(" month "\\) \\([12][0-9]\\{3\\}\\)\\>"))
                  ("Month D, Y" . ,(concat "\\<\\(" month "\\) \\([0-3]?[0-9]\\), \\([12][0-9]\\{3\\}\\)\\>"))))
         (occ (cl-loop for (kind . re) in kinds
                       nconc (well-formed--matches
                              paras re
                              (lambda (text base)
                                (when-let* ((ymd (well-formed--parse-date kind text)))
                                  (list kind (+ base (match-beginning 0)) (+ base (match-end 0)) ymd)))))))
    (well-formed--minority-with
     occ 'date-format
     (lambda (k major n) (format "%s date here; %d elsewhere are %s" k n major))
     (lambda (o major) (well-formed--format-date major (nth 3 o))))))

(defun well-formed--minority-with (occurrences rule describe fix)
  "Like `well-formed--minority' for OCCURRENCES (KEY BEG END . _), keyed by
their car; FIX makes the replacement from an occurrence and the majority key."
  (let ((counts (make-hash-table :test #'equal)))
    (dolist (o occurrences) (cl-incf (gethash (car o) counts 0)))
    (when (> (hash-table-count counts) 1)
      (let (major (best 0))
        (maphash (lambda (k n) (when (> n best) (setq major k best n))) counts)
        (cl-loop for o in occurrences
                 unless (equal (car o) major)
                 collect (list (nth 1 o) (nth 2 o) rule (funcall describe (car o) major best)
                               (delq nil (list (funcall fix o major)))))))))

(defconst well-formed--minor-words
  '("a" "an" "the" "and" "but" "or" "nor" "for" "on" "at" "to" "by" "of" "in" "with"
    "from" "as" "vs" "via" "into" "onto" "per" "than" "up" "off" "out" "over" "so" "yet")
  "Words Title Case leaves in lower case.")

(defun well-formed--heading-case (paras)
  "Headings in Title Case and in Sentence case: the document's majority wins.
Only headings of three words or more, with no masked markup inside, count."
  (let (occ (case-fold-search nil))
    (dolist (p paras)
      (when (and (eq (well-formed-para-kind p) 'heading) (equal (well-formed-para-lang p) "en"))
        (let* ((text (well-formed-para-text p)) (base (well-formed-para-beg p))
               (wb (string-match "[[:alpha:]]" text))
               (we (and wb (let ((i (length text)))
                             (while (and (> i wb) (not (string-match-p "[[:alnum:]?!.)]" (substring text (1- i) i))))
                               (setq i (1- i)))
                             i)))
               (span (and wb (substring text wb we)))
               (words (and span (split-string span "[^[:alpha:]']+" t)))
               (content (mapcar (lambda (w) (cons w (and (string-match-p "\\`[[:upper:]]" w) t)))
                                (seq-remove (lambda (w) (member (downcase w) well-formed--minor-words))
                                            (cdr words))))
               (plain (seq-remove (lambda (c) (string-match-p "\\`.\\(?:.*[[:upper:]]\\)" (car c))) content))
               (upper (cl-count-if #'cdr plain)) (lower (- (length plain) upper)))
          (when (and span (>= (length words) 3) (>= (length plain) 2) (not (string-search "\0" span)))
            (cond ((zerop lower) (push (list "Title Case" (+ base wb) (+ base we) span) occ))
                  ((>= lower (* 2 upper)) (push (list "Sentence case" (+ base wb) (+ base we) span) occ)))))))
    (well-formed--minority-with
     (nreverse occ) 'heading-case
     (lambda (k major n) (format "%s heading; %d others are %s" k n major))
     (lambda (o major)
       (let ((first t) (case-fold-search nil))
         (replace-regexp-in-string
          "[[:alpha:]']+"
          (lambda (w)
            (prog1 (cond (first w)
                         ((member (downcase w) well-formed--minor-words) (downcase w))
                         ((string-match-p "\\`.\\(?:.*[[:upper:]]\\)" w) w) ; GitHub, API: as is
                         ((equal major "Title Case") (capitalize w))
                         (t (downcase w)))
              (setq first nil)))
          (nth 3 o) t t))))))

(defconst well-formed--unit-symbols
  '("KB" "MB" "GB" "TB" "KiB" "MiB" "GiB" "TiB" "ms" "µs" "ns" "Hz" "kHz" "MHz" "GHz"
    "px" "pt" "km" "cm" "mm" "kg" "fps" "dpi" "Mbit" "Gbit")
  "Unit symbols after a number: written with a space (5 GB) or without (5GB).")

(defun well-formed--unit-format (paras)
  "\"5 GB\" here, \"5GB\" there: the document's majority wins."
  (let* ((re (concat "\\<[0-9]+\\(?:[.,][0-9]+\\)?\\( ?\\)\\(" (regexp-opt well-formed--unit-symbols) "\\)\\>"))
         (occ (well-formed--matches
               paras re
               (lambda (text base)
                 (list (if (string-empty-p (match-string 1 text)) "5GB" "5 GB")
                       (+ base (match-beginning 0)) (+ base (match-end 0))
                       (match-string 0 text))))))
    (well-formed--minority-with
     occ 'unit-format
     (lambda (k major n) (format "%s here; %d elsewhere are written %s" (if (equal k "5GB") "No space before the unit" "A space before the unit") n major))
     (lambda (o major)
       (let ((s (nth 3 o)))
         (if (equal major "5 GB")
             (replace-regexp-in-string "\\([0-9]\\)\\([^0-9., ]\\)" "\\1 \\2" s nil nil nil)
           (replace-regexp-in-string "\\([0-9]\\) " "\\1" s)))))))

(defun well-formed--consistency-more (paras)
  (let ((en (cl-remove-if-not (lambda (p) (equal (well-formed-para-lang p) "en")) paras)))
    (unless (memq 'consistency (bound-and-true-p well-formed-disabled-categories))
      (append (and en (well-formed--number-style en))
              (and en (well-formed--term-case en))
              (well-formed--date-format paras)
              (well-formed--unit-format paras)
              (well-formed--heading-case paras)))))

(well-formed-define-rule unit-format
  :category 'consistency :level 'info
  :doc "A unit after a number with a space in some places (5 GB) and
without in others (5GB); the one used more wins."
  :function #'ignore)

(well-formed-define-rule number-style
  :category 'consistency :level 'info :langs '("en")
  :doc "Small numbers (2-9) as digits in some places, as words in others;
the one used more wins.  Digits before units (3 GB, 5 min) don't count."
  :function #'ignore)
(well-formed-define-rule term-case
  :category 'consistency :level 'warning :langs '("en")
  :doc "A term with inner capitals written two ways (GitHub, Github): the
inner-capital form used most wins."
  :function #'ignore)
(well-formed-define-rule date-format
  :category 'consistency :level 'info
  :doc "Dates in two formats (2026-11-05 and 05.11.2026); the one used more
wins, and the fix rewrites the date in it."
  :function #'ignore)
(well-formed-define-rule heading-case
  :category 'consistency :level 'info :langs '("en")
  :doc "Some headings in Title Case, some in Sentence case; the one used
more wins."
  :function #'ignore)

(add-hook 'well-formed-document-functions #'well-formed--consistency-more)

(provide 'well-formed-rules)
;;; well-formed-rules.el ends here
