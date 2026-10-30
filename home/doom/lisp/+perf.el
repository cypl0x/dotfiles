;;; lisp/+perf.el --- Performance fixes, each found by measurement -*- lexical-binding: t; -*-
;;
;; Opening a remote /etc file on a NixOS host (e.g. /ssh:inari:/etc/hosts)
;; froze Emacs at 100% CPU.  /etc files there are symlinks into /nix/store,
;; and on `find-file-hook' doom-modeline asks projectile for the project root,
;; which lists every directory up the tree, so all of remote /nix/store
;; (~80k entries).  TRAMP's `file-name-all-completions' skeleton then merges
;; that listing with `seq-union', which is quadratic: 2.0 s for 8k entries,
;; 4x per doubling, minutes for the store.  Measured 2026-10-30 in `emacs -Q'
;; (seq 2.24 and Emacs 32's built-in seq alike); see JOURNAL.org.
;;
;; Two independent fixes:
;;  1. The store is immutable and never a project: projectile stops looking
;;     for a root inside it, so the listing never happens.
;;  2. `seq-union' on two lists with `equal' semantics runs in linear time,
;;     same result and order, so big remote directories complete quickly.
;;
;;; Code:

(require 'cl-lib)
(require 'seq)

(defun +perf-nix-store-p (path)
  "Non-nil if PATH, local or remote, lies in /nix/store.  Never connects."
  (and path
       (string-prefix-p "/nix/store/"
                        (or (file-remote-p path 'localname) path))))

(defun +perf-projectile-skip-store-a (fn &optional dir)
  "Around `projectile-project-root' (FN): no root for DIR in the store.
DIR defaults to `default-directory'."
  (unless (+perf-nix-store-p (or dir default-directory))
    (funcall fn dir)))

(with-eval-after-load 'projectile
  (advice-add 'projectile-project-root :around #'+perf-projectile-skip-store-a))

(defconst +perf-seq-union-threshold 64
  "Below this combined length the generic `seq-union' is fast enough.")

(cl-defmethod seq-union ((sequence1 list) (sequence2 list) &optional testfn)
  "Linear-time `seq-union' for lists compared with `equal'.
Same result and order as the generic method: SEQUENCE1's elements without
duplicates, then SEQUENCE2's that are new."
  (if (or (not (memq testfn '(nil equal)))
          (< (+ (length sequence1) (length sequence2)) +perf-seq-union-threshold))
      (cl-call-next-method)
    (let ((seen (make-hash-table :test #'equal
                                 :size (+ (length sequence1) (length sequence2))))
          result)
      (dolist (seq (list sequence1 sequence2))
        (dolist (elt seq)
          (unless (gethash elt seen)
            (puthash elt t seen)
            (push elt result))))
      (nreverse result))))

(provide '+perf)
;;; +perf.el ends here
