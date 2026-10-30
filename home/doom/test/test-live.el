;;; test/test-live.el --- Tests against the running Doom session -*- lexical-binding: t; -*-
;;
;; Checks wiring that only exists in a real Doom session: leader keys, menu
;; suffixes, capture templates, snippets. Read-only; safe in your daemon.
;;
;; Run: emacsclient --eval '(load "~/dotfiles/home/doom/test/test-live.el")'
;;      then (test-live-run) returns a one-line summary.
;;
;;; Code:

(require 'ert)

(defconst test-live-lisp-dir (expand-file-name "lisp/" doom-user-dir))

(defun test-live--leader (keys)
  (lookup-key doom-leader-map (kbd keys)))

(defun test-live--menu-suffixes (file)
  "Return (PREFIX . COMMAND) for every suffix in FILE's transient menus."
  (let (out)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (when (eq (car-safe form) 'transient-define-prefix)
                (cl-labels ((walk (x)
                              (cond ((and (consp x) (stringp (car x))
                                          (stringp (car-safe (cdr x)))
                                          (consp (cddr x)) (symbolp (nth 2 x))
                                          (nth 2 x))
                                     (push (cons (nth 1 form) (nth 2 x)) out))
                                    ((consp x) (mapc #'walk (if (proper-list-p x) x
                                                              (list (car x) (cdr x)))))
                                    ((vectorp x) (mapc #'walk x)))))
                  (walk (nthcdr 2 form))))))
        (end-of-file nil)))
    out))

(ert-deftest live/every-menu-suffix-is-callable ()
  "Transient refuses to open a menu with an undefined, non-autoloaded suffix."
  (let (bad)
    (dolist (f (directory-files test-live-lisp-dir t "\\`\\+.*\\.el\\'"))
      (dolist (s (test-live--menu-suffixes f))
        (unless (fboundp (cdr s))
          (push (format "%s: %s" (car s) (cdr s)) bad))))
    (should-not bad)))

(ert-deftest live/leader-keys ()
  (should (eq (test-live--leader "A") '+agent/transient))
  (should (eq (test-live--leader "q R") '+daemon/sync-and-restart))
  (should (eq (test-live--leader "n V") '+vellumory/open-feedback)))

(ert-deftest live/gptel-reads-key-lazily-and-has-model ()
  (require 'gptel)
  (should (functionp (gptel-backend-key gptel-backend)))
  (should (memq gptel-model (gptel-backend-models gptel-backend))))

(ert-deftest live/vellumory-capture-template ()
  (require 'org-capture)
  (should (assoc "V" org-capture-templates)))

(ert-deftest live/private-snippets-dir-exists ()
  (should (file-directory-p (expand-file-name "snippets" doom-user-dir))))

(ert-deftest live/lisp-dir-is-live-checkout ()
  "lisp/ must resolve into the dotfiles checkout, not a store copy."
  (should (string-prefix-p (expand-file-name "~/dotfiles/")
                           (file-truename test-live-lisp-dir))))


(ert-deftest live/familiar-wired ()
  (require 'familiar)
  (require 'git-commit)
  (should (eq (lookup-key git-commit-mode-map (kbd "M-g")) 'familiar-commit-message))
  (should (member familiar--mode-line-construct global-mode-string))
  (should (eq (familiar--model 'commit) 'claude-haiku-5-5))
  ;; The real backend knows the price, so spend is never silently zero.
  (should (> (familiar-cost (familiar--model 'commit) '(:input 1000)) 0)))

(defun test-live-run ()
  "Run live tests; return a summary string."
  (let ((stats (ert-run-tests "\\`live/" #'ignore)))
    (format "%d/%d passed%s"
            (ert-stats-completed-expected stats)
            (ert-stats-total stats)
            (let (fails)
              (dotimes (i (ert-stats-total stats))
                (let ((r (aref (ert--stats-test-results stats) i)))
                  (unless (ert-test-result-expected-p (aref (ert--stats-tests stats) i) r)
                    (push (format "%s: %S" (ert-test-name (aref (ert--stats-tests stats) i))
                                  (and (ert-test-failed-p r)
                                       (ert-test-result-with-condition-condition r)))
                          fails))))
              (if fails (concat " — FAILED " (string-join fails "; ")) "")))))

(provide 'test-live)
;;; test-live.el ends here
