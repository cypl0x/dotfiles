;;; lisp/+brave-search.el --- Brave Search Doom integration -*- lexical-binding: t; -*-
;;
;; Loads brave-search.el from lisp/brave-search/, adds Doom keybindings, and
;; gives M-ß (`familiar-ask') a web_search tool.
;;
;;; Code:

(load! "brave-search/brave-search")

(defvar familiar-ask-tools)
(declare-function familiar-ask--cap "familiar-ask" (text))
(declare-function gptel-make-tool "ext:gptel" (&rest slots))
(declare-function gptel-tool-name "ext:gptel" (tool))

(map! :leader
      (:prefix "s"
       :desc "Brave search"        "b" #'brave-search
       :desc "Brave search region" "B" #'brave-search-region
       :desc "Brave news"          "n" #'brave-search-news-interactive)
      (:prefix "s"
       :desc "Brave transient"     "v" #'brave-search-transient))

;; From the retired +prompt.el, which pushed it (and seven Emacs tools) into
;; the global `gptel-tools'; familiar-ask has its own Emacs tools.
(defun +brave-search--tool (query)
  "The top five web results for QUERY, as Markdown for a model."
  (mapconcat (lambda (r)
               (format "## %s\n%s\n%s\n"
                       (brave-search--decode-entities (alist-get 'title r))
                       (alist-get 'url r)
                       (brave-search--decode-entities (or (alist-get 'description r) ""))))
             (alist-get 'results (alist-get 'web (brave-search-web query :count 5)))
             "\n"))

(with-eval-after-load 'familiar-ask
  (unless (seq-find (lambda (tool) (equal (gptel-tool-name tool) "web_search"))
                    familiar-ask-tools)
    (setq familiar-ask-tools
          (append familiar-ask-tools
                  (list (gptel-make-tool
                         :name "web_search" :category "web"
                         :description "Search the web (Brave Search): the top five results with titles, URLs and snippets. For current facts, or anything outside the user's Emacs."
                         :args '((:name "query" :type string :description "Search query"))
                         :function (lambda (query)
                                     (familiar-ask--cap (+brave-search--tool query)))
                         :include t))))))

(provide '+brave-search)
;;; +brave-search.el ends here
