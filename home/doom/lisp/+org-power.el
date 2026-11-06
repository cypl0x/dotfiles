;;; lisp/+org-power.el --- Org-mode power tools -*- lexical-binding: t; -*-
;;
;; org-roam, org-super-agenda, org-ql, org-modern, org-appear,
;; org-transclusion, org-noter, and advanced capture templates.
;;
;;; Code:

;;;; org-roam — Zettelkasten ─────────────────────────────────────────────────

(use-package! org-roam
  :after org
  :init
  ;; The whole vault is the graph (a note anywhere in it can be linked and
  ;; show backlinks; +org-roam/init makes existing files nodes); new notes
  ;; still go under roam/, the database stays there.
  (setq org-roam-directory org-directory
        org-roam-db-location (expand-file-name "roam/org-roam.db" org-directory)
        org-roam-dailies-directory "roam/daily/"
        org-roam-file-exclude-regexp "\\(?:\\.git/\\|~\\'\\|\\.#\\|#[^/]*#\\'\\)"
        org-roam-completion-everywhere t)
  :config
  (org-roam-db-autosync-mode)

  ;; Capture templates — research, concept, reference, daily
  (setq org-roam-capture-templates
        '(("d" "default" plain "%?"
           :target (file+head "roam/%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags:\n\n")
           :unnarrowed t)
          ("c" "concept" plain
           "* Definition\n%?\n\n* Properties\n\n* Examples\n\n* Related\n"
           :target (file+head "roam/concepts/%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: :concept:\n\n")
           :unnarrowed t)
          ("r" "reference" plain
           "* Source\n- Author: %?\n- URL: \n- Year: \n\n* Summary\n\n* Key Points\n\n* Quotes\n"
           :target (file+head "roam/refs/%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: :reference:\n\n")
           :unnarrowed t)
          ("t" "turm" plain
           "* Context\n%?\n\n* Type Theory\n\n* Implementation Notes\n\n* Proof Sketch\n"
           :target (file+head "roam/turm/%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: :turm:dtt:\n\n")
           :unnarrowed t)))

  (setq org-roam-dailies-capture-templates
        '(("d" "default" entry "* %?"
           :target (file+head "%<%Y-%m-%d>.org"
                              "#+title: %<%Y-%m-%d %A>\n\n")))))

(use-package! consult-org-roam
  ;; With consult: :after org-roam alone loaded consult at startup (0.85 s).
  :after (:all org-roam consult)
  :config
  (consult-org-roam-mode 1))

;;;; org-super-agenda — Grouped agenda views ─────────────────────────────────

(use-package! org-super-agenda
  :after org-agenda
  :config
  (org-super-agenda-mode)
  (setq org-super-agenda-groups
        '((:name "Urgent"
           :priority "A"
           :order 1)
          (:name "In Progress"
           :todo "STRT"
           :order 2)
          (:name "Turm"
           :tag "turm"
           :order 3)
          (:name "Emacs"
           :tag "emacs"
           :order 4)
          (:name "Research"
           :tag "research"
           :order 5)
          (:name "Backlog"
           :priority<= "B"
           :order 10)
          (:auto-category t
           :order 20))))

;;;; org-ql — Query language ─────────────────────────────────────────────────

(use-package! org-ql
  :after org
  :config
  ;; Example saved searches. Extend as needed.
  (setq org-ql-views
        `(("Recent TODOs" .
           (:buffers-files org-agenda-files
            :query (and (todo)
                        (ts :from -7))
            :sort (date)
            :title "Recent TODOs (last 7 days)"))
          ("Turm Tasks" .
           (:buffers-files org-agenda-files
            :query (and (todo)
                        (tags "turm"))
            :sort (priority)
            :title "Turm Tasks"))
          ("Stale TODOs" .
           (:buffers-files org-agenda-files
            :query (and (todo)
                        (not (ts :from -30)))
            :title "Stale TODOs (no timestamp in 30 days)")))))

;;;; org-modern — Visual polish ──────────────────────────────────────────────

(use-package! org-modern
  :after org
  :hook (org-agenda-finalize . org-modern-agenda)
  :config
  ;; Enable org-modern after font-lock is ready, not via hook (avoids
  ;; race condition that disables fontification).
  (add-hook 'org-mode-hook #'org-modern-mode 90)  ; high depth = runs late
  ;; One bullet per Org level face (8), deeper levels cycle like the faces
  ;; (`org-cycle-level-faces').  A list here is the old API: org-modern read
  ;; it as `replace' with its default five, so levels 5+ all got ✳, a
  ;; colour emoji (fixed green) instead of the heading's colour.  All from
  ;; Maple Mono NF: no emoji font, no font search.
  (setq org-modern-star 'replace
        org-modern-replace-stars "◉○◈◇◆◎▸▹"
        org-modern-cycle-stars t
        org-modern-table-vertical 1
        org-modern-table-horizontal 0.2
        org-modern-list '((43 . "➤") (45 . "–") (42 . "•"))
        ;; Labels in the theme's own colours (the keyword's Org face as the
        ;; label background, like org-modern's defaults): see
        ;; `+org-modern-todo-faces-h'.  The old hard-coded white-on-colour labels
        ;; read at WCAG 2.1-2.8; these at 5.2-10.
        org-modern-tag t
        org-modern-timestamp t
        org-modern-block-fringe nil
        org-modern-keyword nil
        ;; Hide leading stars — org-modern renders its own bullets.
        org-hide-leading-stars t
        ;; Markup as in Markdown previews: hidden, revealed at point by
        ;; org-appear (which does nothing while the markers are shown).
        org-hide-emphasis-markers t
        org-pretty-entities t)
  (+org-modern-todo-faces-h)
  (add-hook 'doom-load-theme-hook #'+org-modern-todo-faces-h))

(defun +org-modern-label-face (face-or-colour)
  "A label in FACE-OR-COLOUR (a face's foreground, or a colour string).
Explicit colours, not :inherit: org-modern appends org-modern-label (0.8)
itself, and inheriting faces rendered labels at 14, 18 and 22 px side by
side.  Inverse video, so hl-line's background on the current line becomes
the label's text instead of wiping the label out."
  (list :foreground (cond ((stringp face-or-colour) face-or-colour)
                          ((and face-or-colour (facep face-or-colour))
                           (face-foreground face-or-colour nil t))
                          (t (face-foreground 'shadow nil t)))
        :background (face-background 'default nil t)
        :inverse-video t
        :weight 'semibold))

(defun +org-modern-todo-faces-h ()
  "Keyword and priority labels in the colours Org itself uses for them.
Done items stay muted, in a grey dark text still reads on (WCAG 5.7)."
  ;; doom-color is nil under a theme not from Doom (modus-operandi, your light
  ;; side): Org then failed to load ("Invalid face").
  (let ((muted (or (doom-color 'base7) (face-foreground 'shadow nil t))))
    (setq org-modern-todo-faces
          (append (mapcar (lambda (kf) (cons (car kf) (+org-modern-label-face (cdr kf))))
                          org-todo-keyword-faces)
                  (mapcar (lambda (kw) (cons kw (+org-modern-label-face muted)))
                          '("DONE" "OKAY" "YES" "[X]")))
          org-modern-priority-faces
          `((?A ,@(+org-modern-label-face 'error))
            (?B ,@(+org-modern-label-face 'warning))
            (?C ,@(+org-modern-label-face muted))))))

;;;; org-appear — Auto-reveal markup ─────────────────────────────────────────

;; Markers show only while you write (insert state), not while you read and
;; move: revealed under the cursor in normal state, they shifted the rest of
;; the line sideways (a link 50 px at 4x zoom, measured 2026-11-05; 0 px
;; with this): the "wiggle" going through paragraphs.  org-appear's own
;; recipe for Evil.
(defun +org-appear-evil-h ()
  "Reveal markup only in insert state in this Org buffer."
  (add-hook 'evil-insert-state-entry-hook #'org-appear-manual-start nil t)
  (add-hook 'evil-insert-state-exit-hook #'org-appear-manual-stop nil t))

(use-package! org-appear
  :after org
  :hook (org-mode . org-appear-mode)
  :hook (org-mode . +org-appear-evil-h)
  :config
  (setq org-appear-trigger 'manual)
  ;; Emphasis and links: lisp/+org-links.el shows the object at point as written.
  (setq org-appear-autoemphasis nil
        ;; Links: lisp/+org-links.el shows one as written while point is on it.
        org-appear-autolinks nil
        org-appear-autosubmarkers t
        org-appear-autoentities t
        org-appear-delay 0.3
        org-appear-inside-latex t))

;;;; org-transclusion — Live embedded content ────────────────────────────────

(use-package! org-transclusion
  :after org
  :config
  (map! :map org-mode-map
        :localleader
        (:prefix ("T" . "transclusion")
         :desc "Add"       "a" #'org-transclusion-add
         :desc "Add all"   "A" #'org-transclusion-add-all
         :desc "Remove"    "r" #'org-transclusion-remove
         :desc "Remove all" "R" #'org-transclusion-remove-all
         :desc "Refresh"   "g" #'org-transclusion-refresh
         :desc "Mode"      "t" #'org-transclusion-mode)))

;;;; org-noter — Synchronized annotation ─────────────────────────────────────

(use-package! org-noter
  :defer t                     ; loaded with Org at startup (0.9 s); autoloaded
  :config
  (setq org-noter-notes-search-path (list (expand-file-name "refs" org-directory))
        org-noter-auto-save-last-location t
        org-noter-highlight-selected-text t
        org-noter-always-create-frame nil))

;;;; org-download — Image insertion ──────────────────────────────────────────

(use-package! org-download
  :after org
  :config
  (setq org-download-method 'directory
        org-download-image-dir (expand-file-name "img" org-directory)
        org-download-heading-lvl nil
        org-download-timestamp "%Y%m%d%H%M%S-"))

;;;; Citation management ─────────────────────────────────────────────────────

(use-package! citar
  :after org
  :config
  (setq org-cite-global-bibliography
        (list (expand-file-name "refs/bibliography.bib" org-directory))
        org-cite-insert-processor 'citar
        org-cite-follow-processor 'citar
        org-cite-activate-processor 'citar
        citar-bibliography org-cite-global-bibliography))

(use-package! citar-org-roam
  :after (:all citar org-roam)
  :config
  (citar-org-roam-mode))

;;;; Enhanced capture templates ──────────────────────────────────────────────

;; Everything goes to ~/vault/inbox.org first, as a top-level entry stamped
;; with when it came in (date and time); you or an agent sort it later.
;; Doom's personal templates are replaced (they and these had both t and
;; n, and the second t and n couldn't be reached), its project groups (p,
;; o) stay.  No org-roam IDs: SPC m I gives one when a note needs it.
(defvar +org-capture-inbox (expand-file-name "inbox.org" "~/vault/")
  "Where captures land before they are sorted.")

(defvar +org-capture-templates
  `(("t" "TODO (for me)" entry (file +org-capture-inbox)
     "* TODO %?\n%U\n" :empty-lines 1)
    ("n" "Note" entry (file +org-capture-inbox)
     "* %U %?\n" :empty-lines 1)
    ("a" "TODO for an agent" entry (file +org-capture-inbox)
     "* TODO %? :agent:\n%U\n" :empty-lines 1)
    ("h" "TODO here (links back to where you are)" entry (file +org-capture-inbox)
     "* TODO %?\n%U\n%a\n" :empty-lines 1)
    ("q" "Quote the selection (with where it is from)" entry (file +org-capture-inbox)
     "* %U %?\n#+begin_quote\n%i\n#+end_quote\nFrom: %a\n" :empty-lines 1)
    ("l" "Link (the URL on the clipboard)" entry (file +org-capture-inbox)
     "* %(+org-capture--clip-link)%?\n%U\n" :empty-lines 1)
    ("i" "Idea" entry (file +org-capture-inbox)
     "* IDEA %?\n%U\n" :empty-lines 1)
    ("m" "Meeting" entry (file +org-capture-inbox)
     "* %U Meeting: %?\n** Attendees\n** Notes\n** Actions\n" :empty-lines 1)
    ("j" "Journal (journal.org, by date)" entry (file+olp+datetree "journal.org")
     "* %U %?\n" :empty-lines 1))
  "The capture templates in front of Doom's project groups.")

(defun +org-capture--clip-link ()
  "The clipboard's URL as an Org link (titled when org-cliplink can), or empty."
  (let ((clip (ignore-errors (current-kill 0 t))))
    (cond ((not (and (stringp clip) (string-match-p "\\`https?://" (string-trim clip)))) "")
          ((fboundp 'org-cliplink-capture) (or (ignore-errors (org-cliplink-capture)) (format "[[%s]] " (string-trim clip))))
          (t (format "[[%s]] " (string-trim clip))))))

(defun +org-capture--merge (templates)
  "Ours, then TEMPLATES without the keys ours take: Doom's project groups
and whatever packages added (vellumory's V) stay."
  (append +org-capture-templates
          (seq-remove (lambda (tp) (assoc (car tp) +org-capture-templates)) templates)))

(after! org
  (setq org-capture-templates (+org-capture--merge org-capture-templates)))

;;;; Keybindings — SPC n (notes) ─────────────────────────────────────────────

(map! :leader
      (:prefix "n"
       (:prefix ("r" . "roam")
        :desc "Find node"           "f" #'org-roam-node-find
        :desc "Insert link"         "i" #'org-roam-node-insert
        :desc "Capture"             "c" #'org-roam-capture
        :desc "Backlinks buffer"    "b" #'org-roam-buffer-toggle
        :desc "Consult roam"        "s" #'consult-org-roam-search)
       :desc "org-ql views"         "v" #'org-ql-view
       :desc "org-ql search"        "q" #'org-ql-search
       :desc "Super agenda"         "a" #'org-agenda))

;; Display toggles under Doom's SPC t, as the others: both were run through
;; M-x in the usage log.
(map! :leader
      (:prefix "t"
       :desc "Org modern look"   "o" #'org-modern-mode
       :desc "Org pretty markup" "O" #'+org-pretty-mode))

;;;; Casual Org — what can be done here, as a menu ───────────────────────────

;; From the task list: a discoverable, context-sensitive Org transient.
;; Casual's Org menu (kickingvegas/casual, GPL-3.0) is that: its sections
;; follow where point is (heading, list item, table, block), org-table
;; included.  SPC m m in Org.
(use-package! casual-org
  :defer t
  :init
  (map! :after org :map org-mode-map :localleader
        :desc "What can I do here (menu)" "m" #'casual-org-tmenu))


;;;; SPC m . (consult-org-heading): TODO states in front, as in the agenda

;; consult puts the TODO keyword in a right-aligned annotation, after the
;; longest outline path, which in a big file is past the window edge.  It
;; goes in front of the heading now, in Org's colors; the annotation keeps
;; the priority.
(defun +org-consult-todo-first-a (cands)
  "Filter for `consult-org--headings' CANDS: the TODO keyword first."
  (mapcar (lambda (cand)
            (pcase-let* ((props (text-properties-at 0 cand))
                         (`(,_level ,todo ,_prio . ,buffer) (plist-get props 'consult-org--heading)))
              (if (not todo) cand
                (let* ((cut (if (and buffer (string-prefix-p buffer cand)) (1+ (length buffer)) 0))
                       (new (concat (substring cand 0 cut) todo " " (substring cand cut))))
                  (add-text-properties 0 1 props new)
                  new))))
          cands))

(defun +org-consult-priority-only-a (fn cand)
  "Around `consult-org--annotate' (FN): the priority only (TODO is in front)."
  ;; The property is a dotted (LEVEL TODO PRIO . BUFFER): rebuilt, not
  ;; `copy-sequence'd, which older Emacsen (neomacs) refuse on dotted lists.
  (pcase-let ((`(,level ,_todo ,prio . ,buffer) (get-text-property 0 'consult-org--heading cand))
              (copy (copy-sequence cand)))
    (put-text-property 0 1 'consult-org--heading `(,level nil ,prio . ,buffer) copy)
    (funcall fn copy)))

(with-eval-after-load 'consult-org
  (advice-add 'consult-org--headings :filter-return #'+org-consult-todo-first-a)
  (advice-add 'consult-org--annotate :around #'+org-consult-priority-only-a))
(provide '+org-power)
;;; +org-power.el ends here

;;;; The fringe: wide enough to click, and clicks that do something

;; In Org the left fringe is `+org-fringe-width' pixels (Emacs' default is
;; 8, hard to hit).  A click there shows the change on that line (diff-hl)
;; if there is one; on a heading without one it folds or unfolds it.
(defvar +org-fringe-width 16 "Left fringe width in Org buffers, in pixels.")

(declare-function diff-hl-hunk-overlay-at "ext:diff-hl" (pos))
(declare-function diff-hl-show-hunk "ext:diff-hl-show-hunk" ())
(declare-function org-at-heading-p "org" (&optional invisible-not-ok))
(declare-function org-cycle "org-cycle" (&optional arg))

(defun +org-wide-fringe-h ()
  "A clickable left fringe in this Org buffer and its windows."
  (setq-local left-fringe-width +org-fringe-width)
  (dolist (w (get-buffer-window-list nil nil t))
    (set-window-fringes w +org-fringe-width nil)))

(defun +org-fringe-click (event)
  "Show the change at the clicked line, or fold the heading there."
  (interactive "e")
  (posn-set-point (event-start event))
  (cond ((and (bound-and-true-p diff-hl-mode) (diff-hl-hunk-overlay-at (point)))
         (diff-hl-show-hunk))
        ((and (derived-mode-p 'org-mode) (save-excursion (beginning-of-line) (org-at-heading-p)))
         (beginning-of-line) (org-cycle))))

(defun +org-fringe-click-a (fn event)
  "Around diff-hl's fringe click (FN): in Org, headings fold where no change is."
  (if (derived-mode-p 'org-mode) (+org-fringe-click event) (funcall fn event)))

(add-hook 'org-mode-hook #'+org-wide-fringe-h)
(with-eval-after-load 'org
  (define-key org-mode-map [left-fringe mouse-1] #'+org-fringe-click))
(with-eval-after-load 'diff-hl-show-hunk
  (advice-add 'diff-hl-show-hunk--click :around #'+org-fringe-click-a))
