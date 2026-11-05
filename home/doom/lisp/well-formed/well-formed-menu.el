;;; well-formed-menu.el --- One menu for well-formed -*- lexical-binding: t; -*-
;;
;;; Commentary:
;;
;; M-x well-formed-menu: the finding at point (fix, ignore, explain), the
;; buffer (list, report, fix a rule throughout), the style, and which
;; categories speak; each shows its current state.
;;
;;; Code:

(require 'transient)
(require 'well-formed)

(declare-function well-formed-report "well-formed-report" (&optional beg end))

(defun well-formed-menu--here ()
  (if-let* (((bound-and-true-p well-formed-mode))
            (f (car (ignore-errors (well-formed--at (point))))))
      (format "Here: %s" (propertize (nth 4 f) 'face (pcase (nth 3 f) ('error 'error) ('warning 'warning) (_ 'shadow))))
    (format "Here: %s" (propertize "nothing" 'face 'shadow))))

(defun well-formed-menu--counts ()
  (let ((found (and (bound-and-true-p well-formed-mode) (ignore-errors (well-formed--ensure-findings)))))
    (format "%s style, %s · %d findings%s"
            (car (well-formed--document-settings))
            (let ((g (well-formed--document-goals))) (format "for %s readers, to %s" (car g) (cdr g)))
            (length found)
            (if found
                (concat " ("
                        (mapconcat (lambda (c)
                                     (format "%s %d" (downcase (cdr c))
                                             (cl-count-if (lambda (f) (eq (well-formed-rule-category (well-formed--rule (nth 2 f))) (car c)))
                                                          found)))
                                   well-formed-categories ", ")
                        ")")
              ""))))

(defun well-formed-menu--category (cat)
  (format "%s %s" (alist-get cat well-formed-categories)
          (if (memq cat well-formed-disabled-categories) (propertize "off" 'face 'shadow)
            (propertize "on" 'face 'success))))

(defmacro well-formed-menu--toggle (cat)
  `(lambda () (interactive) (well-formed-toggle-category ',cat) (transient-setup 'well-formed-menu)))

(defalias 'well-formed-menu--toggle-correctness (well-formed-menu--toggle correctness))
(defalias 'well-formed-menu--toggle-clarity (well-formed-menu--toggle clarity))
(defalias 'well-formed-menu--toggle-engagement (well-formed-menu--toggle engagement))
(defalias 'well-formed-menu--toggle-delivery (well-formed-menu--toggle delivery))
(defalias 'well-formed-menu--toggle-consistency (well-formed-menu--toggle consistency))

;;;###autoload (autoload 'well-formed-menu "well-formed-menu" nil t)
(transient-define-prefix well-formed-menu ()
  "well-formed: the finding here, the whole text, style and categories."
  [:description well-formed-menu--counts
   ["Here" :description well-formed-menu--here
    ("f" "fix" well-formed-fix)
    ("i" "ignore…" well-formed-ignore)
    ("e" "explain the rule" well-formed-explain)
    ("n" "next finding" well-formed-next :transient t)
    ("p" "previous finding" well-formed-previous :transient t)]
   ["Text"
    ("l" "list every finding" well-formed-list)
    ("r" "report: scores, tone, readability" well-formed-report)
    ("a" "fix one rule throughout" well-formed-fix-all)
    ("u" "stop ignoring…" well-formed-unignore)
    ("m" "checking on/off here" well-formed-mode)]
   ["Style"
    ("s" "style for this buffer…" well-formed-set-style)
    ("g" "goals: audience, intent…" well-formed-set-goals)]
   ["Categories"
    ("1" well-formed-menu--toggle-correctness :description (lambda () (well-formed-menu--category 'correctness)))
    ("2" well-formed-menu--toggle-clarity :description (lambda () (well-formed-menu--category 'clarity)))
    ("3" well-formed-menu--toggle-engagement :description (lambda () (well-formed-menu--category 'engagement)))
    ("4" well-formed-menu--toggle-delivery :description (lambda () (well-formed-menu--category 'delivery)))
    ("5" well-formed-menu--toggle-consistency :description (lambda () (well-formed-menu--category 'consistency)))]])


(provide 'well-formed-menu)
;;; well-formed-menu.el ends here
