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
  (setq org-roam-directory (expand-file-name "roam" org-directory)
        org-roam-db-location (expand-file-name "org-roam.db" org-roam-directory)
        org-roam-dailies-directory "daily/"
        org-roam-completion-everywhere t)
  :config
  (org-roam-db-autosync-mode)

  ;; Capture templates — research, concept, reference, daily
  (setq org-roam-capture-templates
        '(("d" "default" plain "%?"
           :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags:\n\n")
           :unnarrowed t)
          ("c" "concept" plain
           "* Definition\n%?\n\n* Properties\n\n* Examples\n\n* Related\n"
           :target (file+head "concepts/%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: :concept:\n\n")
           :unnarrowed t)
          ("r" "reference" plain
           "* Source\n- Author: %?\n- URL: \n- Year: \n\n* Summary\n\n* Key Points\n\n* Quotes\n"
           :target (file+head "refs/%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: :reference:\n\n")
           :unnarrowed t)
          ("t" "turm" plain
           "* Context\n%?\n\n* Type Theory\n\n* Implementation Notes\n\n* Proof Sketch\n"
           :target (file+head "turm/%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+filetags: :turm:dtt:\n\n")
           :unnarrowed t)))

  (setq org-roam-dailies-capture-templates
        '(("d" "default" entry "* %?"
           :target (file+head "%<%Y-%m-%d>.org"
                              "#+title: %<%Y-%m-%d %A>\n\n")))))

(use-package! consult-org-roam
  :after org-roam
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
  (setq org-modern-star '("◉" "○" "◈" "◇" "▸")
        org-modern-table-vertical 1
        org-modern-table-horizontal 0.2
        org-modern-list '((43 . "➤") (45 . "–") (42 . "•"))
        org-modern-todo-faces
        '(("TODO" :background "#ff6c6b" :foreground "white" :weight bold)
          ("STRT" :background "#da8548" :foreground "white" :weight bold)
          ("DONE" :background "#98be65" :foreground "white" :weight bold))
        org-modern-priority-faces
        '((?A :background "#ff6c6b" :foreground "white" :weight bold)
          (?B :background "#da8548" :foreground "white")
          (?C :background "#5B6268" :foreground "white"))
        org-modern-tag t
        org-modern-timestamp t
        org-modern-block-fringe nil
        org-modern-keyword nil
        ;; Hide leading stars — org-modern renders its own bullets.
        org-hide-leading-stars t))

;;;; org-appear — Auto-reveal markup ─────────────────────────────────────────

(use-package! org-appear
  :after org
  :hook (org-mode . org-appear-mode)
  :config
  (setq org-appear-autoemphasis t
        org-appear-autolinks t
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
  :after (:any org pdf-view)
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

(after! org
  ;; Extend org-capture beyond org-roam (which handles note capture).
  ;; These are for quick task/inbox capture.
  (setq org-capture-templates
        (append org-capture-templates
                '(("t" "Task" entry
                   (file+headline "inbox.org" "Tasks")
                   "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n"
                   :empty-lines 1)
                  ("n" "Note" entry
                   (file+headline "inbox.org" "Notes")
                   "* %? :note:\n:PROPERTIES:\n:CREATED: %U\n:END:\n"
                   :empty-lines 1)
                  ("l" "Link" entry
                   (file+headline "inbox.org" "Links")
                   "* %? :link:\n:PROPERTIES:\n:URL: %^{URL}\n:CREATED: %U\n:END:\n"
                   :empty-lines 1)))))

;;;; Keybindings — SPC n (notes) ─────────────────────────────────────────────

(map! :leader
      (:prefix "n"
       (:prefix ("r" . "roam")
        :desc "Find node"           "f" #'org-roam-node-find
        :desc "Insert link"         "i" #'org-roam-node-insert
        :desc "Capture"             "c" #'org-roam-capture
        :desc "Backlinks buffer"    "b" #'org-roam-buffer-toggle
        :desc "Graph"               "g" #'org-roam-graph
        :desc "Dailies today"       "t" #'org-roam-dailies-goto-today
        :desc "Dailies capture"     "d" #'org-roam-dailies-capture-today
        :desc "Consult roam"        "s" #'consult-org-roam-search)
       :desc "org-ql views"         "v" #'org-ql-view
       :desc "org-ql search"        "q" #'org-ql-search
       :desc "Super agenda"         "a" #'org-agenda))

(provide '+org-power)
;;; +org-power.el ends here
