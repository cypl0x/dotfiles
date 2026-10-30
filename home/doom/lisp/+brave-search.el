;;; lisp/+brave-search.el --- Brave Search Doom integration -*- lexical-binding: t; -*-
;;
;; Loads brave-search.el from lisp/brave-search/ and adds Doom keybindings.
;;
;;; Code:

(load! "brave-search/brave-search")

(map! :leader
      (:prefix "s"
       :desc "Brave search"        "b" #'brave-search
       :desc "Brave search region" "B" #'brave-search-region
       :desc "Brave news"          "n" #'brave-search-news-interactive)
      (:prefix "s"
       :desc "Brave transient"     "v" #'brave-search-transient))

(provide '+brave-search)
;;; +brave-search.el ends here
