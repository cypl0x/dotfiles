;;; familiar-analytics.el --- What familiar costs, does and could do better -*- lexical-binding: t; -*-
;;
;; M-x familiar-analytics (Doom: SPC o $): one buffer about every request
;; familiar made, from its ledger (each request priced) and its history
;; (each prompt):
;;
;;   Figures          spend, requests, tokens, cache hits, budget left and
;;                    when it runs out at the recent pace
;;   Plots            spend per day (bars) with the cumulative line against
;;                    the budget; tokens in/out per day; when you ask, as a
;;                    weekday × hour heatmap; cost per task and per model
;;   Statistics       per task and per model: requests, share of spend,
;;                    mean / median / p95 cost, tokens, output per input
;;   Data             the most expensive requests, linked to their prompts
;;   Insights and     rules over all of the above, each with the numbers
;;   recommendations  behind it: a task on a dearer tier than its answers
;;                    need, prompts that would cache, bursts, the forecast
;;
;; Graphics are SVG where Emacs can show them, text (▁▂▃▅▇) otherwise.
;; Keys: r range (all, 30, 7 days, today) · g refresh · RET the request's
;; prompt in the history · e the data as CSV · q quit.
;;
;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'svg)
(require 'iso8601)

(defvar familiar-budget)
(defvar familiar-models)
(defvar familiar-task-tiers)
(defvar familiar-history-directory)
(declare-function familiar--ledger "familiar" ())
(declare-function familiar-cost "familiar" (model tokens))
(declare-function org-back-to-heading "org" (&optional invisible-ok))
(declare-function org-fold-show-entry "org-fold" (&optional hide-drawers))

(defgroup familiar-analytics nil
  "Analytics of familiar's requests."
  :group 'familiar)

(defcustom familiar-analytics-top 12
  "How many of the most expensive requests to list."
  :type 'integer)

(defcustom familiar-analytics-conversation-tasks (quote (ask acp a2a openai atuin))
  "Tasks that are conversations: each tool-call round is its own request,
so short answers and bursts are how they work, not a waste."
  :type (quote (repeat symbol)))

(defun familiar-analytics--automatic (groups)
  "GROUPS without the conversation tasks."
  (seq-remove (lambda (g) (memq (car g) familiar-analytics-conversation-tasks)) groups))

(defface familiar-analytics-heading '((t :inherit (outline-1 bold) :height 1.15))
  "Section headings in `familiar-analytics'.")

;;;; Data

(cl-defstruct (familiar-analytics--req (:constructor familiar-analytics--req-make)
                                       (:copier nil))
  time model task in out cached cost)

(defun familiar-analytics--requests (&optional since)
  "Ledger entries as structs, oldest first; only from SINCE (a time) on."
  (let (out)
    (dolist (e (familiar--ledger))
      (let ((time (ignore-errors (encode-time (iso8601-parse (nth 0 e))))))
        (when (and time (or (null since) (not (time-less-p time since))))
          (push (familiar-analytics--req-make
                 :time time :model (nth 1 e) :task (nth 2 e) :in (or (nth 3 e) 0)
                 :out (or (nth 4 e) 0) :cached (or (nth 5 e) 0) :cost (or (nth 6 e) 0.0))
                out))))
    (nreverse out)))

(defun familiar-analytics--sum (fn reqs) (apply #'+ 0 (mapcar fn reqs)))

(defun familiar-analytics--quantile (values q)
  "The Q quantile (0–1) of VALUES (numbers), nearest rank."
  (when values
    (let ((sorted (sort (copy-sequence values) #'<)))
      (nth (min (1- (length sorted)) (max 0 (1- (ceiling (* q (length sorted)))))) sorted))))

(defun familiar-analytics--day (time) (format-time-string "%Y-%m-%d" time))

(defun familiar-analytics--group (key reqs)
  "REQS grouped by KEY (a function): alist (VALUE . REQS), biggest spend first."
  (let ((table (make-hash-table :test #'equal)) groups)
    (dolist (r reqs) (push r (gethash (funcall key r) table)))
    (maphash (lambda (k v) (push (cons k (nreverse v)) groups)) table)
    (sort groups (lambda (a b) (> (familiar-analytics--sum #'familiar-analytics--req-cost (cdr a))
                                  (familiar-analytics--sum #'familiar-analytics--req-cost (cdr b)))))))

(defun familiar-analytics--days (reqs)
  "Every day from the first request in REQS to today: alist (DAY . REQS), in order."
  (when reqs
    (let* ((by-day (familiar-analytics--group (lambda (r) (familiar-analytics--day (familiar-analytics--req-time r))) reqs))
           (day (familiar-analytics--req-time (car reqs)))
           (today (familiar-analytics--day nil))
           days)
      (while (progn (let ((d (familiar-analytics--day day)))
                      (push (cons d (cdr (assoc d by-day))) days)
                      (setq day (time-add day 86400))
                      (string< d today))))
      (nreverse days))))

;;;; Numbers

(defun familiar-analytics--usd (x)
  (cond ((>= x 1) (format "$%.2f" x)) ((>= x 0.01) (format "$%.3f" x)) (t (format "$%.5f" x))))

(defun familiar-analytics--tokens (n)
  (cond ((>= n 1e6) (format "%.1fM" (/ n 1e6))) ((>= n 1e3) (format "%.1fk" (/ n 1e3))) (t (format "%d" n))))

(defun familiar-analytics--pct (part whole) (if (zerop whole) 0 (* 100.0 (/ (float part) whole))))

(defun familiar-analytics--figures (reqs all)
  "Headline numbers for REQS (the range) and ALL (for the budget): a plist."
  (let* ((spent-all (familiar-analytics--sum #'familiar-analytics--req-cost all))
         (week (seq-filter (lambda (r) (time-less-p (time-subtract nil (* 7 86400)) (familiar-analytics--req-time r))) all))
         (week-days (max 1.0 (min 7.0 (/ (float-time (time-subtract nil (familiar-analytics--req-time (or (car all) (familiar-analytics--req-make :time nil))))) 86400))))
         (rate (/ (familiar-analytics--sum #'familiar-analytics--req-cost week) week-days))
         (left (and familiar-budget (- familiar-budget spent-all))))
    (list :requests (length reqs)
          :spent (familiar-analytics--sum #'familiar-analytics--req-cost reqs)
          :in (familiar-analytics--sum #'familiar-analytics--req-in reqs)
          :out (familiar-analytics--sum #'familiar-analytics--req-out reqs)
          :cached (familiar-analytics--sum #'familiar-analytics--req-cached reqs)
          :spent-all spent-all :rate rate :left left
          :runs-out (and left (> rate 0) (time-add nil (* 86400 (/ left rate)))))))

;;;; Charts

(defun familiar-analytics--svg-p () (and (display-graphic-p) (image-type-available-p 'svg)))

(defun familiar-analytics--color (face attr fallback)
  (let ((c (face-attribute face attr nil t))) (if (and (stringp c) (not (string-prefix-p "unspecified" c))) c fallback)))

(defun familiar-analytics--palette ()
  (list :fg (familiar-analytics--color 'default :foreground "#bbc2cf")
        :bg (familiar-analytics--color 'default :background "#242730")
        :dim (familiar-analytics--color 'shadow :foreground "#5b6268")
        :a (familiar-analytics--color 'font-lock-function-name-face :foreground "#51afef")
        :b (familiar-analytics--color 'font-lock-string-face :foreground "#7bc275")
        :c (familiar-analytics--color 'warning :foreground "#FCCE7B")
        :d (familiar-analytics--color 'error :foreground "#ff665c")))

(defun familiar-analytics--chart-width ()
  (max 360 (min 1100 (- (window-body-width nil t) 40))))

(defun familiar-analytics--insert-svg (svg alt)
  (insert-image (svg-image svg :ascent 'center) alt)
  (insert "\n"))

(defun familiar-analytics--spark (values)
  (let ((max (apply #'max 1e-9 values)))
    (mapconcat (lambda (v) (string (aref "▁▂▃▄▅▆▇█" (min 7 (floor (* 7.99 (/ (float v) max))))))) values "")))

(defun familiar-analytics--daily-chart (days budget)
  "Bars of spend per day, the cumulative line, BUDGET as a rule."
  (let* ((costs (mapcar (lambda (d) (familiar-analytics--sum #'familiar-analytics--req-cost (cdr d))) days))
         (cum (let ((s 0)) (mapcar (lambda (c) (setq s (+ s c))) costs))))
    (if (not (familiar-analytics--svg-p))
        (insert (format "  per day  %s  max %s\n  in total %s  %s\n"
                        (familiar-analytics--spark costs) (familiar-analytics--usd (apply #'max 0 costs))
                        (familiar-analytics--spark cum) (familiar-analytics--usd (car (last cum)))))
      (let* ((p (familiar-analytics--palette))
             (w (familiar-analytics--chart-width)) (h 200) (left 56) (bottom 22) (top 26)
             (n (length days)) (bw (/ (float (- w left 10)) (max 1 n)))
             (max-day (apply #'max 1e-9 costs))
             (max-cum (max (car (last cum)) (if (and budget (< (car (last cum)) budget)
                                                    (> (car (last cum)) (* 0.25 budget)))
                                                budget 0)))
             (plot-h (- h top bottom))
             (svg (svg-create w h)))
        (svg-rectangle svg 0 0 w h :fill (plist-get p :bg))
        ;; Bars (left axis: per day).
        (cl-loop for c in costs for i from 0
                 do (let ((bh (* plot-h (/ c max-day))))
                      (svg-rectangle svg (+ left (* i bw) 1) (- h bottom bh) (max 1 (- bw 2)) bh
                                     :fill (plist-get p :a) :fill-opacity 0.75)))
        ;; Cumulative line (right scale).
        (svg-polyline svg (cl-loop for c in cum for i from 0
                                   collect (cons (+ left (* (+ i 0.5) bw)) (- h bottom (* plot-h (/ c (max max-cum 1e-9))))))
                      :fill "none" :stroke (plist-get p :c) :stroke-width 2)
        (when (and budget (<= budget max-cum))
          (let ((y (- h bottom (* plot-h (/ budget max-cum)))))
            (svg-line svg left y w y :stroke (plist-get p :d) :stroke-dasharray "4,4")
            (svg-text svg (format "budget %s" (familiar-analytics--usd budget)) :x (- w 110) :y (- y 4)
                      :fill (plist-get p :d) :font-size 11)))
        (svg-text svg (familiar-analytics--usd max-day) :x 2 :y (+ top 10) :fill (plist-get p :dim) :font-size 11)
        (svg-text svg "$0" :x 2 :y (- h bottom) :fill (plist-get p :dim) :font-size 11)
        ;; Legend above the plot, so it never sits on the line.
        (svg-rectangle svg left 6 10 10 :fill (plist-get p :a) :fill-opacity 0.75)
        (svg-text svg "per day (left scale)" :x (+ left 14) :y 15 :fill (plist-get p :dim) :font-size 11)
        (svg-line svg (+ left 150) 11 (+ left 166) 11 :stroke (plist-get p :c) :stroke-width 2)
        (svg-text svg (format "in total: %s (top = %s)" (familiar-analytics--usd (car (last cum))) (familiar-analytics--usd max-cum))
                  :x (+ left 170) :y 15 :fill (plist-get p :c) :font-size 11)
        (svg-text svg (car (car days)) :x left :y (- h 6) :fill (plist-get p :dim) :font-size 11)
        (svg-text svg (car (car (last days))) :x (- w 80) :y (- h 6) :fill (plist-get p :dim) :font-size 11)
        (familiar-analytics--insert-svg svg (format "[spend per day, total %s]" (familiar-analytics--usd (car (last cum)))))))))

(defun familiar-analytics--tokens-chart (days)
  "Tokens in (up) and out (down) per day, mirrored."
  (let ((ins (mapcar (lambda (d) (familiar-analytics--sum #'familiar-analytics--req-in (cdr d))) days))
        (outs (mapcar (lambda (d) (familiar-analytics--sum #'familiar-analytics--req-out (cdr d))) days)))
    (if (not (familiar-analytics--svg-p))
        (insert (format "  in   %s\n  out  %s\n" (familiar-analytics--spark ins) (familiar-analytics--spark outs)))
      (let* ((p (familiar-analytics--palette)) (w (familiar-analytics--chart-width)) (h 130) (left 56)
             (mid (/ h 2)) (n (length days)) (bw (/ (float (- w left 10)) (max 1 n)))
             (mx (apply #'max 1 (append ins outs))) (svg (svg-create w h)))
        (svg-rectangle svg 0 0 w h :fill (plist-get p :bg))
        (cl-loop for i from 0 for in in ins for out in outs
                 do (let ((x (+ left (* i bw) 1)) (ih (* (- mid 8) (/ (float in) mx))) (oh (* (- mid 8) (/ (float out) mx))))
                      (svg-rectangle svg x (- mid ih) (max 1 (- bw 2)) ih :fill (plist-get p :a) :fill-opacity 0.7)
                      (svg-rectangle svg x mid (max 1 (- bw 2)) oh :fill (plist-get p :b) :fill-opacity 0.7)))
        (svg-line svg left mid w mid :stroke (plist-get p :dim))
        (svg-text svg "in" :x 2 :y 16 :fill (plist-get p :a) :font-size 11)
        (svg-text svg "out" :x 2 :y (- h 6) :fill (plist-get p :b) :font-size 11)
        (svg-text svg (familiar-analytics--tokens mx) :x 24 :y 16 :fill (plist-get p :dim) :font-size 11)
        (familiar-analytics--insert-svg svg "[tokens per day]")))))

(defun familiar-analytics--heatmap (reqs)
  "Requests by weekday and hour."
  (let ((grid (make-vector 168 0)))
    (dolist (r reqs)
      (let ((d (decode-time (familiar-analytics--req-time r))))
        (cl-incf (aref grid (+ (* 24 (mod (+ 6 (decoded-time-weekday d)) 7)) (decoded-time-hour d))))))
    (let ((mx (max 1 (seq-max grid))) (names '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun")))
      (if (not (familiar-analytics--svg-p))
          (cl-loop for day below 7
                   do (insert (format "  %s %s\n" (nth day names)
                                      (mapconcat (lambda (h) (let ((v (aref grid (+ (* 24 day) h))))
                                                               (if (zerop v) "·" (string (aref "░▒▓█" (min 3 (floor (* 3.99 (/ (float v) mx)))))))))
                                                 (number-sequence 0 23) ""))))
        (let* ((p (familiar-analytics--palette)) (cell 18) (left 40) (top 16)
               (svg (svg-create (+ left (* 24 cell) 10) (+ top (* 7 cell) 6))))
          (svg-rectangle svg 0 0 (+ left (* 24 cell) 10) (+ top (* 7 cell) 6) :fill (plist-get p :bg))
          (dotimes (h 24)
            (when (zerop (mod h 3))
              (svg-text svg (format "%02d" h) :x (+ left (* h cell) 2) :y 12 :fill (plist-get p :dim) :font-size 10)))
          (dotimes (day 7)
            (svg-text svg (nth day names) :x 4 :y (+ top (* day cell) 13) :fill (plist-get p :dim) :font-size 11)
            (dotimes (h 24)
              (let ((v (aref grid (+ (* 24 day) h))))
                (svg-rectangle svg (+ left (* h cell)) (+ top (* day cell)) (- cell 2) (- cell 2)
                               :fill (if (zerop v) (plist-get p :dim) (plist-get p :b))
                               :fill-opacity (if (zerop v) 0.15 (+ 0.25 (* 0.75 (/ (float v) mx))))
                               :rx 3))))
          (familiar-analytics--insert-svg svg "[requests by weekday and hour]"))))))

(defun familiar-analytics--bars (groups total)
  "Horizontal bars: share of TOTAL spend per group of GROUPS."
  (let ((width (max 10 (- (window-body-width) 60))))
    (dolist (g groups)
      (let* ((cost (familiar-analytics--sum #'familiar-analytics--req-cost (cdr g)))
             (share (if (zerop total) 0 (/ cost total)))
             (n (round (* width share))))
        (insert (format "  %-20s " (truncate-string-to-width (format "%s" (car g)) 20))
                (propertize (make-string (max (if (> cost 0) 1 0) n) ?█) 'face 'font-lock-function-name-face)
                (format " %s  %4.1f%%  (%d)\n" (familiar-analytics--usd cost) (* 100 share) (length (cdr g))))))))

;;;; Tables

(defun familiar-analytics--stats-table (groups label total)
  "A table of GROUPS (first column LABEL), shares of TOTAL spend."
  (let* ((rows
          (cons (list label "requests" "spend" "share" "mean" "median" "p95" "in" "out" "out/in" "cached")
                (mapcar
                 (lambda (g)
                   (let* ((rs (cdr g)) (costs (mapcar #'familiar-analytics--req-cost rs))
                          (in (familiar-analytics--sum #'familiar-analytics--req-in rs))
                          (out (familiar-analytics--sum #'familiar-analytics--req-out rs))
                          (cached (familiar-analytics--sum #'familiar-analytics--req-cached rs))
                          (spend (apply #'+ costs)))
                     (list (format "%s" (car g)) (number-to-string (length rs)) (familiar-analytics--usd spend)
                           (format "%.1f%%" (familiar-analytics--pct spend total))
                           (familiar-analytics--usd (/ spend (length rs)))
                           (familiar-analytics--usd (familiar-analytics--quantile costs 0.5))
                           (familiar-analytics--usd (familiar-analytics--quantile costs 0.95))
                           (familiar-analytics--tokens in) (familiar-analytics--tokens out)
                           (format "%.2f" (if (zerop in) 0 (/ (float out) in)))
                           (format "%.0f%%" (familiar-analytics--pct cached (+ in cached))))))
                 groups)))
         (widths (apply #'cl-mapcar (lambda (&rest col) (apply #'max (mapcar #'string-width col))) rows)))
    (cl-loop for row in rows for first = t then nil
             do (insert "  "
                        (mapconcat #'identity
                                   (cl-loop for cell in row for w in widths for i from 0
                                            collect (if (zerop i) (string-pad cell w) (string-pad cell w nil t)))
                                   "  ")
                        "\n")
             (when first
               (insert "  " (propertize (make-string (+ (apply #'+ widths) (* 2 (1- (length widths)))) ?─) 'face 'shadow) "\n")))))

;;;; Insights

(defun familiar-analytics--tier-of (model)
  (car (rassoc model (bound-and-true-p familiar-models))))

(defun familiar-analytics-insights (reqs all figures)
  "Insights over REQS (the range), ALL and FIGURES: list of (LEVEL TITLE TEXT)."
  (let (out
        (total (plist-get figures :spent))
        (fast (alist-get 'fast (bound-and-true-p familiar-models))))
    ;; The budget at this pace.
    (when-let* ((left (plist-get figures :left)) (rate (plist-get figures :rate)))
      (push (if (plist-get figures :runs-out)
                (let ((days (/ left (max rate 1e-9))))
                  (list (if (< days 14) 'warning 'info) "Budget forecast"
                        (format "%s of %s left; at the last week's %s a day it lasts %s (until %s)."
                                (familiar-analytics--usd left) (familiar-analytics--usd familiar-budget)
                                (familiar-analytics--usd rate)
                                (if (> days 365) "over a year" (format "%d days" (round days)))
                                (format-time-string "%Y-%m-%d" (plist-get figures :runs-out)))))
              (list 'info "Budget forecast" "Nothing spent in the last week."))
            out))
    ;; A task on a dearer tier whose answers are short: the fast tier would do.
    (when fast
      (dolist (g (familiar-analytics--automatic (familiar-analytics--group #'familiar-analytics--req-task reqs)))
        (let* ((rs (cdr g))
               (dear (seq-remove (lambda (r) (equal (familiar-analytics--req-model r) fast)) rs))
               (median-out (familiar-analytics--quantile (mapcar #'familiar-analytics--req-out dear) 0.5)))
          (when (and (>= (length dear) 5) median-out (< median-out 300))
            (let* ((now (familiar-analytics--sum #'familiar-analytics--req-cost dear))
                   (then (familiar-analytics--sum
                          (lambda (r) (or (ignore-errors
                                            (familiar-cost fast (list :input (familiar-analytics--req-in r)
                                                                      :output (familiar-analytics--req-out r)
                                                                      :cached (familiar-analytics--req-cached r))))
                                          (familiar-analytics--req-cost r)))
                          dear)))
              (when (> (- now then) 0.005)
                (push (list 'recommend (format "Task %s could run on the fast tier" (car g))
                            (format "%d requests on %s, answers %d tokens at the median: short enough for %s. That would have cost %s instead of %s. Set (setf (alist-get '%s familiar-task-tiers) 'fast)."
                                    (length dear) (mapconcat #'symbol-name (delete-dups (mapcar #'familiar-analytics--req-model dear)) ", ")
                                    median-out fast (familiar-analytics--usd then) (familiar-analytics--usd now) (car g)))
                      out)))))))
    ;; Big prompts that never hit the cache.
    (let* ((big (seq-filter (lambda (r) (> (familiar-analytics--req-in r) 4000)) reqs))
           (uncached (seq-filter (lambda (r) (zerop (familiar-analytics--req-cached r))) big)))
      (when (and (>= (length uncached) 3) (> (length uncached) (* 0.8 (length big))))
        (push (list 'recommend "Large prompts aren't cached"
                    (format "%d of %d requests over 4k input tokens had no cache hits (%s input). Prompt caching bills repeated input at a tenth; it pays where the same context (a buffer, a diff) is sent again within minutes."
                            (length uncached) (length big)
                            (familiar-analytics--tokens (familiar-analytics--sum #'familiar-analytics--req-in uncached))))
              out)))
    ;; Where the money goes.
    (when-let* ((top (car (familiar-analytics--group #'familiar-analytics--req-task reqs)))
                ((> total 0)))
      (let ((share (familiar-analytics--pct (familiar-analytics--sum #'familiar-analytics--req-cost (cdr top)) total)))
        (when (> share 40)
          (push (list 'info (format "%s is %.0f%% of the spend" (car top) share)
                      (format "%d requests, %s. Its p95 request costs %s."
                              (length (cdr top)) (familiar-analytics--usd (familiar-analytics--sum #'familiar-analytics--req-cost (cdr top)))
                              (familiar-analytics--usd (familiar-analytics--quantile (mapcar #'familiar-analytics--req-cost (cdr top)) 0.95))))
                out))))
    ;; Conversations: rounds within a minute re-send the growing context.
    (let* ((conv (seq-filter (lambda (r) (memq (familiar-analytics--req-task r) familiar-analytics-conversation-tasks)) reqs))
           (rounds (cl-loop for (a b) on conv
                            when (and b (< (float-time (time-subtract (familiar-analytics--req-time b) (familiar-analytics--req-time a))) 60))
                            collect b))
           (in (familiar-analytics--sum #'familiar-analytics--req-in rounds))
           (cached (familiar-analytics--sum #'familiar-analytics--req-cached rounds)))
      (when (>= (length rounds) 5)
        (push (list (if (< (familiar-analytics--pct cached (+ in cached)) 50) 'recommend 'info)
                    "Follow-up rounds re-send the conversation"
                    (format "%d of %d conversation requests came within a minute of the one before (tool calls, follow-ups): %s input, %s of it (%.0f%%) from the cache, %s spent. %s"
                            (length rounds) (length conv) (familiar-analytics--tokens (+ in cached))
                            (familiar-analytics--tokens cached) (familiar-analytics--pct cached (+ in cached))
                            (familiar-analytics--usd (familiar-analytics--sum #'familiar-analytics--req-cost rounds))
                            (if (< (familiar-analytics--pct cached (+ in cached)) 50)
                                "Caching the system prompt, tools and earlier turns would bill most of that input at a tenth."
                              "Caching already covers most of it.")))
              out)))
    ;; Bursts: many requests of one task within a minute.
    (dolist (g (familiar-analytics--automatic (familiar-analytics--group #'familiar-analytics--req-task reqs)))
      (let ((times (mapcar (lambda (r) (float-time (familiar-analytics--req-time r))) (cdr g))) (worst 0))
        (cl-loop for (a . rest) on times
                 do (setq worst (max worst (1+ (cl-count-if (lambda (b) (< (- b a) 60)) rest)))))
        (when (>= worst 8)
          (push (list 'recommend (format "Bursts of %s" (car g))
                      (format "Up to %d %s requests within one minute: the trigger fires more often than you can read the answers; a longer idle delay or a per-minute cap would save them."
                              worst (car g)))
                out))))
    ;; Outliers: single requests far above their task's usual cost.
    (let ((outliers (cl-loop for g in (familiar-analytics--automatic (familiar-analytics--group #'familiar-analytics--req-task reqs))
                             for med = (familiar-analytics--quantile (mapcar #'familiar-analytics--req-cost (cdr g)) 0.5)
                             append (seq-filter (lambda (r) (and (> (length (cdr g)) 4)
                                                                 (> (familiar-analytics--req-cost r) (* 20 (max med 1e-6)))
                                                                 (> (familiar-analytics--req-cost r) 0.01)))
                                                (cdr g)))))
      (when outliers
        (push (list 'info (format "%d outlier request%s" (length outliers) (if (cdr outliers) "s" ""))
                    (mapconcat (lambda (r) (format "%s %s %s (%s in)" (format-time-string "%m-%d %H:%M" (familiar-analytics--req-time r))
                                                   (familiar-analytics--req-task r) (familiar-analytics--usd (familiar-analytics--req-cost r))
                                                   (familiar-analytics--tokens (familiar-analytics--req-in r))))
                               (seq-take outliers 5) "; "))
              out)))
    (ignore all)
    (nreverse out)))

;;;; The buffer

(defvar-local familiar-analytics--days nil "The range shown: nil (all) or a number of days.")

(defun familiar-analytics--heading (title)
  (insert "\n" (propertize title 'face 'familiar-analytics-heading) "\n\n"))

(defun familiar-analytics--render ()
  (let* ((inhibit-read-only t)
         (all (familiar-analytics--requests))
         (since (and familiar-analytics--days
                     (if (zerop familiar-analytics--days)
                         (date-to-time (format-time-string "%F 00:00"))
                       (time-subtract nil (* 86400 familiar-analytics--days)))))
         (reqs (if since (familiar-analytics--requests since) all))
         (figs (familiar-analytics--figures reqs all))
         (total (plist-get figs :spent))
         (days (familiar-analytics--days reqs)))
    (erase-buffer)
    (insert (propertize "familiar: analytics" 'face '(:inherit familiar-analytics-heading :height 1.3))
            (propertize (format "   %s · r range · g refresh · RET prompt · e CSV\n"
                                (pcase familiar-analytics--days ('nil "all time") (0 "today") (n (format "last %d days" n))))
                        'face 'shadow))
    (if (null reqs)
        (insert "\nNo requests in this range.\n")
      ;; Figures
      (familiar-analytics--heading "Figures")
      (let ((in (plist-get figs :in)) (cached (plist-get figs :cached)))
        (insert (format "  %s spent on %d requests  ·  %s a request  ·  %s in, %s out  ·  %.0f%% of input from cache\n"
                        (propertize (familiar-analytics--usd total) 'face 'bold) (plist-get figs :requests)
                        (familiar-analytics--usd (/ total (max 1 (plist-get figs :requests))))
                        (familiar-analytics--tokens in) (familiar-analytics--tokens (plist-get figs :out))
                        (familiar-analytics--pct cached (+ in cached))))
        (when (plist-get figs :left)
          (insert (format "  Budget: %s of %s used (%.1f%%), %s left; last week %s a day%s\n"
                          (familiar-analytics--usd (plist-get figs :spent-all)) (familiar-analytics--usd familiar-budget)
                          (familiar-analytics--pct (plist-get figs :spent-all) familiar-budget)
                          (familiar-analytics--usd (plist-get figs :left)) (familiar-analytics--usd (plist-get figs :rate))
                          (if (plist-get figs :runs-out)
                              (format-time-string ", runs out around %Y-%m-%d" (plist-get figs :runs-out)) "")))))
      ;; Plots
      (familiar-analytics--heading "Spend per day, and in total")
      (familiar-analytics--daily-chart days (and (null since) familiar-budget))
      (familiar-analytics--heading "Tokens per day")
      (familiar-analytics--tokens-chart days)
      (familiar-analytics--heading "When you ask")
      (familiar-analytics--heatmap reqs)
      (familiar-analytics--heading "Where it goes: tasks")
      (familiar-analytics--bars (familiar-analytics--group #'familiar-analytics--req-task reqs) total)
      (familiar-analytics--heading "Where it goes: models")
      (familiar-analytics--bars (familiar-analytics--group #'familiar-analytics--req-model reqs) total)
      ;; Statistics
      (familiar-analytics--heading "Statistics per task")
      (familiar-analytics--stats-table (familiar-analytics--group #'familiar-analytics--req-task reqs) "task" total)
      (familiar-analytics--heading "Statistics per model")
      (familiar-analytics--stats-table (familiar-analytics--group #'familiar-analytics--req-model reqs) "model" total)
      ;; Insights
      (familiar-analytics--heading "Insights and recommendations")
      (dolist (i (familiar-analytics-insights reqs all figs))
        (pcase-let ((`(,level ,title ,text) i))
          (insert "  " (pcase level ('warning (propertize "⚠" 'face 'warning))
                         ('recommend (propertize "➜" 'face 'success))
                         (_ (propertize "•" 'face 'font-lock-function-name-face)))
                  " " (propertize title 'face 'bold) "\n")
          (let ((start (point)))
            (insert "    " text "\n")
            (let ((fill-column (min 100 (- (window-body-width) 4))) (fill-prefix "    "))
              (fill-region start (point))))))
      ;; Data
      (familiar-analytics--heading (format "The %d most expensive requests" familiar-analytics-top))
      (dolist (r (seq-take (sort (copy-sequence reqs) (lambda (a b) (> (familiar-analytics--req-cost a) (familiar-analytics--req-cost b))))
                           familiar-analytics-top))
        (insert (propertize (format "  %s  %-16s %-20s %8s  %7s in  %6s out\n"
                                    (format-time-string "%Y-%m-%d %H:%M" (familiar-analytics--req-time r))
                                    (familiar-analytics--req-task r) (familiar-analytics--req-model r)
                                    (familiar-analytics--usd (familiar-analytics--req-cost r))
                                    (familiar-analytics--tokens (familiar-analytics--req-in r))
                                    (familiar-analytics--tokens (familiar-analytics--req-out r)))
                            'familiar-analytics-req r))))
    (goto-char (point-min))))

(defun familiar-analytics-visit ()
  "The prompt of the request at point, in familiar's history."
  (interactive)
  (let* ((r (or (get-text-property (point) 'familiar-analytics-req) (user-error "No request on this line")))
         (time (familiar-analytics--req-time r))
         (file (expand-file-name (format-time-string "%Y-%m.org" time) familiar-history-directory))
         (stamp (format-time-string "%Y-%m-%d %a %H:%M" time)))
    (unless (file-exists-p file) (user-error "No history for %s (history keeps asks, not background tasks)" (format-time-string "%Y-%m" time)))
    (find-file-other-window file)
    (goto-char (point-min))
    (if (search-forward (substring stamp 0 10) nil t)
        (progn (search-forward (substring stamp -5) nil t) (org-back-to-heading t) (org-fold-show-entry))
      (message "Not in the history (background requests aren't kept there)"))))

(defun familiar-analytics-range ()
  "Choose the range: all time, 30 or 7 days, today."
  (interactive)
  (setq familiar-analytics--days
        (pcase (completing-read "Range: " '("all time" "last 30 days" "last 7 days" "today") nil t)
          ("all time" nil) ("last 30 days" 30) ("last 7 days" 7) ("today" 0)))
  (familiar-analytics--render))

(defun familiar-analytics-refresh ()
  (interactive)
  (familiar-analytics--render))

(defun familiar-analytics-csv (file)
  "Write every request in the ledger to FILE as CSV."
  (interactive (list (read-file-name "CSV file: " nil nil nil "familiar-requests.csv")))
  (with-temp-file file
    (insert "time,model,task,input,output,cached,usd\n")
    (dolist (r (familiar-analytics--requests))
      (insert (format "%s,%s,%s,%d,%d,%d,%.7f\n"
                      (format-time-string "%FT%T%z" (familiar-analytics--req-time r))
                      (familiar-analytics--req-model r) (familiar-analytics--req-task r)
                      (familiar-analytics--req-in r) (familiar-analytics--req-out r)
                      (familiar-analytics--req-cached r) (familiar-analytics--req-cost r)))))
  (message "Wrote %s" (abbreviate-file-name file)))

(defvar-keymap familiar-analytics-mode-map
  :parent special-mode-map
  "RET" #'familiar-analytics-visit  "r" #'familiar-analytics-range
  "g" #'familiar-analytics-refresh  "e" #'familiar-analytics-csv)

(define-derived-mode familiar-analytics-mode special-mode "familiar analytics"
  "Analytics of familiar's requests (see `familiar-analytics')."
  (setq-local truncate-lines t))

;;;###autoload
(defun familiar-analytics ()
  "Figures, plots, statistics and recommendations about familiar's requests."
  (interactive)
  (require 'familiar)
  (let ((buf (get-buffer-create "*familiar analytics*")))
    (pop-to-buffer buf)
    (unless (derived-mode-p 'familiar-analytics-mode) (familiar-analytics-mode))
    (familiar-analytics--render)))

(provide 'familiar-analytics)
;;; familiar-analytics.el ends here
