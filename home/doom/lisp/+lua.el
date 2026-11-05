;;; lisp/+lua.el --- Lua, with Hyprland's config in mind -*- lexical-binding: t; -*-
;;
;; Hyprland is configured in Lua from 0.55 on (hyprlang goes in 0.57).  Doom's
;; :lang lua (+lsp +tree-sitter) brings lua-ts-mode and lua-language-server;
;; this adds what editing hyprland.lua wants:
;;
;;   - Hyprland's API in the language server: the type stubs Hyprland ships
;;     (share/hypr/stubs/hl.meta.lua, the installed version's own) are a
;;     LuaLS library, so `hl.' completes, every function and dispatcher has
;;     its signature and docs at point, and wrong arguments are diagnosed.
;;   - selene, the Lua linter, in flycheck after luac's syntax check, with a
;;     Hyprland "std" (selene.toml next to the config) so `hl' is known.
;;   - SPC c f formats with stylua (the region, or the buffer).
;;   - SPC m e r / SPC m e e / SPC m e b: evaluate the region, the line, the
;;     buffer inside the running Hyprland (hyprctl eval); SPC m '  a Lua
;;     REPL in the compositor (hyprctl repl); SPC m r reload; SPC m c
;;     the config errors Hyprland reports.  Hyprland evaluates Lua only
;;     with the Lua config loaded; until then these say so.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function flycheck-define-command-checker "ext:flycheck" (symbol docstring &rest properties))
(declare-function flycheck-add-next-checker "ext:flycheck" (checker next &optional append))
(declare-function flycheck-error-new-at "ext:flycheck" (line column &optional level message &rest args))
(declare-function flycheck-valid-checker-p "ext:flycheck" (checker))
(defvar flycheck-checkers)
(defvar eglot-workspace-configuration)

;;;; Hyprland's API in the language server

(defun +lua-hyprland-stubs ()
  "The directory of the running Hyprland's Lua stubs, or nil."
  ;; hyprctl, not Hyprland: that one is a setcap wrapper in /run/wrappers.
  (when-let* ((bin (or (executable-find "hyprctl") (executable-find "Hyprland")))
              (dir (expand-file-name "../share/hypr/stubs" (file-name-directory (file-truename bin))))
              ((file-exists-p (expand-file-name "hl.meta.lua" dir))))
    dir))

(defun +lua-workspace-configuration ()
  "lua-language-server settings: Lua 5.4, Hyprland's API as a library."
  (let ((stubs (+lua-hyprland-stubs)))
    `(:runtime (:version "Lua 5.4")
      :workspace (:library ,(if stubs (vector stubs) []) :checkThirdParty :json-false)
      :diagnostics (:globals ["hl"])
      :completion (:callSnippet "Replace")
      :hint (:enable t)
      :telemetry (:enable :json-false))))

(after! eglot
  ;; Other servers ignore the :Lua section.
  (setq-default eglot-workspace-configuration
                (plist-put (copy-sequence (default-value 'eglot-workspace-configuration))
                           :Lua (+lua-workspace-configuration))))

;;;; Hyprland files

(defun +lua-hyprland-file-p (&optional file)
  "Whether FILE (default: this buffer's) is a Hyprland Lua config."
  (let ((file (or file buffer-file-name)))
    (and file (string-suffix-p ".lua" file)
         (string-match-p "/hypr\\(?:land\\)?/" (file-truename file)))))

(defun +lua--hyprctl (&rest args)
  "Run hyprctl ARGS; its output, trimmed."
  (with-temp-buffer
    (apply #'call-process "hyprctl" nil t nil args)
    (string-trim (buffer-string))))

(defun +lua--lua-config-active-p ()
  (not (string-match-p "only supported with the lua config" (+lua--hyprctl "repl" "return 1"))))

(defun +lua/hypr-eval (beg end)
  "Run the Lua between BEG and END inside the running Hyprland."
  (interactive (if (use-region-p) (list (region-beginning) (region-end))
                 (list (line-beginning-position) (line-end-position))))
  (let ((out (+lua--hyprctl "repl" (buffer-substring-no-properties beg end))))
    (if (string-match-p "only supported with the lua config" out)
        (user-error "Hyprland evaluates Lua only with hyprland.lua loaded (it reads hyprland.conf now)")
      (message "Hyprland: %s" (if (string-empty-p out) "ok" out)))))

(defun +lua/hypr-eval-buffer ()
  "Run this buffer's Lua inside the running Hyprland."
  (interactive)
  (+lua/hypr-eval (point-min) (point-max)))

(defun +lua/hypr-repl ()
  "A Lua REPL inside the running Hyprland (hyprctl repl), in comint."
  (interactive)
  (unless (+lua--lua-config-active-p)
    (user-error "Hyprland evaluates Lua only with hyprland.lua loaded (it reads hyprland.conf now)"))
  (pop-to-buffer (make-comint "hyprland-lua" "hyprctl" nil "repl")))

(defun +lua/hypr-reload ()
  "Reload Hyprland's config and show what it says."
  (interactive)
  (message "Hyprland: %s" (+lua--hyprctl "reload"))
  (+lua/hypr-config-errors t))

(defun +lua/hypr-config-errors (&optional quiet)
  "Show the config errors Hyprland reports (QUIET: only if there are any)."
  (interactive)
  (let ((out (+lua--hyprctl "configerrors")))
    (if (or (string-empty-p out) (string-match-p "\\`no errors" (downcase out)))
        (unless quiet (message "Hyprland: no config errors"))
      (with-current-buffer (get-buffer-create "*hyprland config errors*")
        (let ((inhibit-read-only t)) (erase-buffer) (insert out "\n"))
        (special-mode)
        (display-buffer (current-buffer))))))

(map! :after lua-ts-mode :map lua-ts-mode-map :localleader
      (:prefix ("e" . "eval in Hyprland")
       "r" #'+lua/hypr-eval "e" #'+lua/hypr-eval "b" #'+lua/hypr-eval-buffer)
      "'" #'+lua/hypr-repl "r" #'+lua/hypr-reload "c" #'+lua/hypr-config-errors)
(map! :after lua-mode :map lua-mode-map :localleader
      (:prefix ("e" . "eval in Hyprland")
       "r" #'+lua/hypr-eval "e" #'+lua/hypr-eval "b" #'+lua/hypr-eval-buffer)
      "'" #'+lua/hypr-repl "r" #'+lua/hypr-reload "c" #'+lua/hypr-config-errors)

;;;; selene in flycheck

(defun +lua--selene-errors (output checker buffer)
  "flycheck errors from selene's --display-style=json2 OUTPUT."
  (let (errors)
    (dolist (line (split-string output "\n" t))
      (when-let* ((d (ignore-errors (json-parse-string line :object-type 'plist :null-object nil)))
                  ((equal (plist-get d :type) "Diagnostic"))
                  (span (plist-get (plist-get d :primary_label) :span)))
        (push (flycheck-error-new-at
               (1+ (plist-get span :start_line)) (1+ (plist-get span :start_column))
               (pcase (plist-get d :severity) ("Error" 'error) ("Warning" 'warning) (_ 'info))
               (plist-get d :message)
               :id (plist-get d :code) :checker checker :buffer buffer
               :end-line (1+ (plist-get span :end_line)) :end-column (1+ (plist-get span :end_column)))
              errors)))
    (nreverse errors)))

(defun +lua--selene-after-eglot-h ()
  "Chain selene after `eglot-check' (defined once eglot and flycheck meet), once."
  (when (and (featurep 'flycheck) (flycheck-valid-checker-p 'eglot-check)
             (not (member '(warning . lua-selene) (get 'eglot-check 'flycheck-next-checkers))))
    (flycheck-add-next-checker 'eglot-check '(warning . lua-selene) t)))

(after! flycheck
  (flycheck-define-command-checker 'lua-selene
    "Lua linter selene (https://github.com/Kampfkarren/selene)."
    :command '("selene" "--display-style=json2" "--no-summary" "-")
    :standard-input t
    :error-parser #'+lua--selene-errors
    :modes '(lua-mode lua-ts-mode)
    :working-directory (lambda (_) (or (locate-dominating-file default-directory "selene.toml")
                                      default-directory))
    :predicate (lambda () (executable-find "selene")))
  (add-to-list 'flycheck-checkers 'lua-selene t)
  ;; After luac's syntax check (flycheck's `lua'), and after the language
  ;; server (Doom's `eglot-check'), which is the checker once eglot runs.
  (flycheck-add-next-checker 'lua '(warning . lua-selene) t)
  (add-hook 'eglot-managed-mode-hook #'+lua--selene-after-eglot-h)
  (dolist (mode '(lua-mode lua-ts-mode))
    (unless (memq mode (get 'lua 'flycheck-modes))
      (put 'lua 'flycheck-modes (cons mode (get 'lua 'flycheck-modes))))))

;;;; stylua for SPC c f

(defun +lua-stylua (beg end)
  "Format BEG..END (the buffer if nil) with stylua; point stays put."
  (unless (executable-find "stylua") (user-error "stylua isn't installed"))
  (let* ((buf (current-buffer))
         (args (append (list "--stdin-filepath" (or buffer-file-name "stdin.lua"))
                       (when beg (list "--range-start" (number-to-string (1- (position-bytes beg)))
                                       "--range-end" (number-to-string (1- (position-bytes end)))))
                       (list "-"))))
    (with-temp-buffer
      (let ((out (current-buffer)))
        (with-current-buffer buf
          (apply #'call-process-region (point-min) (point-max) "stylua" nil (list out nil) nil args))
        (if (zerop (buffer-size out))
            (user-error "stylua: the code doesn't parse")
          (with-current-buffer buf
            (replace-region-contents (point-min) (point-max) out 1.0)))))))

(provide '+lua)
;;; +lua.el ends here
