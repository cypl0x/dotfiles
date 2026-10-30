;;; brave-search.el --- Brave Web Search API client for Emacs -*- lexical-binding: t; -*-
;;
;; Author: Wolfhard Prell <mail@wolfhard.net>
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: web, search, tools
;; URL: https://github.com/wolfhard/brave-search.el
;;
;;; Commentary:
;;
;; Full-featured Brave Web Search API client for Emacs.
;; Supports web, news, video, image search, freshness filters,
;; safe search, pagination, extra snippets, and result filtering.
;;
;; API key from ~/.authinfo:
;;   machine api.search.brave.com login apikey password YOUR_KEY
;;
;;; Code:

(require 'url)
(require 'json)
(require 'auth-source)

;;;; Customization ───────────────────────────────────────────────────────────

(defgroup brave-search nil
  "Brave Web Search API client."
  :group 'tools
  :prefix "brave-search-")

(defcustom brave-search-api-url "https://api.search.brave.com/res/v1"
  "Brave Search API base URL."
  :type 'string)

(defcustom brave-search-default-count 10
  "Default number of results per query."
  :type 'integer)

(defcustom brave-search-country "ALL"
  "Default country code for results (e.g. DE, US, ALL)."
  :type 'string)

(defcustom brave-search-safesearch "moderate"
  "Safe search level: off, moderate, strict."
  :type '(choice (const "off") (const "moderate") (const "strict")))

(defcustom brave-search-language "en"
  "Default search language."
  :type 'string)

(defcustom brave-search-extra-snippets nil
  "When non-nil, request extra snippets per result."
  :type 'boolean)

(defcustom brave-search-result-format 'org
  "Output format: `org' for org-mode buffer, `alist' for raw data."
  :type '(choice (const org) (const alist)))

;;;; API key ─────────────────────────────────────────────────────────────────

(defvar brave-search--api-key nil
  "Cached API key.")

(defun brave-search--get-key ()
  "Get Brave Search API key from auth-source."
  (or brave-search--api-key
      (setq brave-search--api-key
            (or (auth-source-pick-first-password :host "api.search.brave.com")
                (user-error "No Brave API key. Add to ~/.authinfo: machine api.search.brave.com login apikey password YOUR_KEY")))))

;;;; HTML entity decoding ────────────────────────────────────────────────────

(defun brave-search--decode-entities (str)
  "Decode HTML entities in STR to plain text."
  (when str
    (with-temp-buffer
      (insert str)
      (goto-char (point-min))
      ;; Named entities
      (while (re-search-forward "&amp;" nil t) (replace-match "&" t t))
      (goto-char (point-min))
      (while (re-search-forward "&lt;" nil t) (replace-match "<" t t))
      (goto-char (point-min))
      (while (re-search-forward "&gt;" nil t) (replace-match ">" t t))
      (goto-char (point-min))
      (while (re-search-forward "&quot;" nil t) (replace-match "\"" t t))
      (goto-char (point-min))
      (while (re-search-forward "&#x27;" nil t) (replace-match "'" t t))
      (goto-char (point-min))
      (while (re-search-forward "&apos;" nil t) (replace-match "'" t t))
      (goto-char (point-min))
      ;; Numeric entities &#NNN; and &#xHHH;
      (while (re-search-forward "&#x\\([0-9a-fA-F]+\\);" nil t)
        (replace-match (string (string-to-number (match-string 1) 16)) t t))
      (goto-char (point-min))
      (while (re-search-forward "&#\\([0-9]+\\);" nil t)
        (replace-match (string (string-to-number (match-string 1))) t t))
      ;; Strip remaining HTML tags
      (goto-char (point-min))
      (while (re-search-forward "<[^>]+>" nil t)
        (replace-match "" t t))
      (buffer-string))))

;;;; HTTP request ────────────────────────────────────────────────────────────

(defun brave-search--request (endpoint params)
  "Send GET request to ENDPOINT with PARAMS alist. Return parsed JSON."
  (let* ((key (brave-search--get-key))
         (query-string (mapconcat
                        (lambda (p)
                          (format "%s=%s"
                                  (url-hexify-string (car p))
                                  (url-hexify-string (cdr p))))
                        (seq-filter (lambda (p) (cdr p)) params)
                        "&"))
         (url (format "%s/%s?%s" brave-search-api-url endpoint query-string))
         (url-request-extra-headers
          `(("Accept" . "application/json")
            ("Accept-Encoding" . "gzip")
            ("X-Subscription-Token" . ,key)))
         (buf (url-retrieve-synchronously url t)))
    (unwind-protect
        (with-current-buffer buf
          (goto-char (point-min))
          (re-search-forward "\n\n")
          (json-parse-buffer :object-type 'alist :array-type 'list))
      (kill-buffer buf))))

;;;; Search functions ────────────────────────────────────────────────────────

(cl-defun brave-search-web (query &key count offset country language
                                  safesearch freshness result-filter
                                  extra-snippets spellcheck)
  "Search Brave Web for QUERY. Returns parsed JSON response.
All keyword args optional, fall back to defcustom defaults."
  (brave-search--request
   "web/search"
   `(("q" . ,query)
     ("count" . ,(number-to-string (or count brave-search-default-count)))
     ("offset" . ,(when offset (number-to-string offset)))
     ("country" . ,(or country brave-search-country))
     ("search_lang" . ,(or language brave-search-language))
     ("safesearch" . ,(or safesearch brave-search-safesearch))
     ("freshness" . ,freshness)
     ("result_filter" . ,result-filter)
     ("extra_snippets" . ,(when (or extra-snippets brave-search-extra-snippets) "true"))
     ("spellcheck" . ,(if (eq spellcheck nil) nil (if spellcheck "true" "false")))
     ("text_decorations" . "false"))))

(defun brave-search-news (query &optional count)
  "Search Brave News for QUERY."
  (brave-search--request
   "news/search"
   `(("q" . ,query)
     ("count" . ,(number-to-string (or count 10))))))

(defun brave-search-images (query &optional count)
  "Search Brave Images for QUERY."
  (brave-search--request
   "images/search"
   `(("q" . ,query)
     ("count" . ,(number-to-string (or count 10))))))

(defun brave-search-videos (query &optional count)
  "Search Brave Videos for QUERY."
  (brave-search--request
   "videos/search"
   `(("q" . ,query)
     ("count" . ,(number-to-string (or count 10))))))

;;;; Result formatting ───────────────────────────────────────────────────────

(defun brave-search--format-web-results (query data)
  "Format web search DATA for QUERY as org content."
  (let ((results (alist-get 'results (alist-get 'web data)))
        (query-info (alist-get 'query data))
        (infobox (alist-get 'infobox data))
        (news (alist-get 'results (alist-get 'news data)))
        (videos (alist-get 'results (alist-get 'videos data)))
        (faq (alist-get 'results (alist-get 'faq data))))
    (with-temp-buffer
      (insert (format "#+title: %s\n" (brave-search--decode-entities query)))
      (insert (format "#+date: %s\n" (format-time-string "%Y-%m-%d %H:%M")))
      (insert (format "#+property: BRAVE_QUERY %s\n\n" query))
      ;; Query metadata
      (when-let ((altered (alist-get 'altered query-info)))
        (insert (format "Spell correction: =%s= → =%s=\n\n"
                        (alist-get 'original query-info) altered)))
      ;; Infobox
      (when infobox
        (when-let ((results (alist-get 'results infobox)))
          (let ((r (if (listp results) (car results) results)))
            (when-let ((desc (alist-get 'long_desc r)))
              (insert "* Summary\n")
              (insert (brave-search--decode-entities desc))
              (insert "\n\n")))))
      ;; FAQ
      (when faq
        (insert "* FAQ\n")
        (dolist (f faq)
          (insert (format "** %s\n%s\n\n"
                          (brave-search--decode-entities (alist-get 'question f))
                          (brave-search--decode-entities (alist-get 'answer f))))))
      ;; Web results
      (insert "* Web Results\n\n")
      (let ((i 1))
        (dolist (r results)
          (let ((title (brave-search--decode-entities (alist-get 'title r)))
                (url (alist-get 'url r))
                (desc (brave-search--decode-entities (or (alist-get 'description r) "")))
                (age (alist-get 'age r)))
            (insert (format "** %d. %s\n" i title))
            (insert (format "[[%s]]\n" url))
            (when age (insert (format "/%s/\n" age)))
            (insert (format "\n%s\n\n" desc))
            ;; Extra snippets
            (when-let ((extras (alist-get 'extra_snippets r)))
              (dolist (s extras)
                (insert (format "#+begin_quote\n%s\n#+end_quote\n\n"
                                (brave-search--decode-entities s)))))
            (cl-incf i))))
      ;; News
      (when news
        (insert "* News\n\n")
        (dolist (n news)
          (insert (format "** %s\n[[%s]]\n/%s/\n\n%s\n\n"
                          (brave-search--decode-entities (alist-get 'title n))
                          (alist-get 'url n)
                          (or (alist-get 'age n) "")
                          (brave-search--decode-entities
                           (or (alist-get 'description n) ""))))))
      ;; Videos
      (when videos
        (insert "* Videos\n\n")
        (dolist (v videos)
          (insert (format "** %s\n[[%s]]\n\n"
                          (brave-search--decode-entities (alist-get 'title v))
                          (alist-get 'url v)))))
      (buffer-string))))

;;;; Interactive commands ────────────────────────────────────────────────────

(defun brave-search (query)
  "Search Brave for QUERY, display results in org buffer."
  (interactive "sBrave Search: ")
  (let* ((data (brave-search-web query))
         (content (brave-search--format-web-results query data))
         (buf (get-buffer-create (format "*Brave: %s*" query))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert content)
        (goto-char (point-min))
        (org-mode)
        (view-mode 1)))
    (pop-to-buffer buf)))

(defun brave-search-region ()
  "Search Brave for selected region text."
  (interactive)
  (unless (use-region-p) (user-error "No active region"))
  (brave-search (buffer-substring-no-properties
                 (region-beginning) (region-end))))

(defun brave-search-at-point ()
  "Search Brave for symbol or word at point."
  (interactive)
  (brave-search (or (thing-at-point 'symbol t)
                     (thing-at-point 'word t)
                     (read-string "Brave Search: "))))

(defun brave-search-lucky (query)
  "Open first Brave result in browser."
  (interactive "sBrave (Lucky): ")
  (let* ((data (brave-search-web query :count 1))
         (url (alist-get 'url (car (alist-get 'results (alist-get 'web data))))))
    (if url (browse-url url)
      (user-error "No results for: %s" query))))

(defun brave-search-news-interactive (query)
  "Search Brave News for QUERY."
  (interactive "sBrave News: ")
  (let* ((data (brave-search-news query))
         (results (alist-get 'results (alist-get 'news data)))
         (buf (get-buffer-create (format "*Brave News: %s*" query))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "#+title: News: %s\n#+date: %s\n\n"
                        query (format-time-string "%Y-%m-%d %H:%M")))
        (dolist (n (or results '()))
          (insert (format "* %s\n[[%s]]\n/%s/\n\n%s\n\n"
                          (brave-search--decode-entities (alist-get 'title n))
                          (alist-get 'url n)
                          (or (alist-get 'age n) "")
                          (brave-search--decode-entities
                           (or (alist-get 'description n) "")))))
        (goto-char (point-min))
        (org-mode)
        (view-mode 1)))
    (pop-to-buffer buf)))

(defun brave-search-with-freshness (query freshness)
  "Search Brave for QUERY with FRESHNESS filter.
FRESHNESS: pd (past day), pw (past week), pm (past month), py (past year),
or YYYY-MM-DDtoYYYY-MM-DD for custom range."
  (interactive
   (list (read-string "Brave Search: ")
         (completing-read "Freshness: "
                          '("pd" "pw" "pm" "py") nil nil)))
  (let* ((data (brave-search-web query :freshness freshness))
         (content (brave-search--format-web-results query data))
         (buf (get-buffer-create (format "*Brave: %s (%s)*" query freshness))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert content)
        (goto-char (point-min))
        (org-mode)
        (view-mode 1)))
    (pop-to-buffer buf)))

(defun brave-search-page-next ()
  "Fetch next page of results for current Brave search buffer."
  (interactive)
  (let* ((query (save-excursion
                  (goto-char (point-min))
                  (when (re-search-forward "^#+property: BRAVE_QUERY \\(.+\\)$" nil t)
                    (match-string 1))))
         (offset (1+ (or (get-text-property (point-min) 'brave-offset) 0))))
    (unless query (user-error "Not in a Brave search buffer"))
    (let* ((data (brave-search-web query :offset offset))
           (content (brave-search--format-web-results query data)))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert content)
        (put-text-property (point-min) (1+ (point-min)) 'brave-offset offset)
        (goto-char (point-min))
        (org-mode)
        (view-mode 1)))))

;;;; Transient ───────────────────────────────────────────────────────────────

(when (require 'transient nil t)
  (transient-define-prefix brave-search-transient ()
    "Brave Search dispatch."
    ["Search"
     ("s" "Web search"       brave-search)
     ("r" "Search region"    brave-search-region)
     ("." "Search at point"  brave-search-at-point)
     ("l" "Lucky (first)"    brave-search-lucky)]
    ["Filtered"
     ("n" "News"             brave-search-news-interactive)
     ("f" "With freshness"   brave-search-with-freshness)]
    ["Navigate"
     ("N" "Next page"        brave-search-page-next)]))

(provide 'brave-search)
;;; brave-search.el ends here
