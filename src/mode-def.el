;;; emmet-mode.el --- Unofficial Emmet's support for emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2021-     Mou Tong           (@dalugm       https://github.com/dalugm)
;; Copyright (C) 2014-     Dmitry Mukhutdinov (@flyingleafe  https://github.com/flyingleafe)
;; Copyright (C) 2014-     William David Mayo (@pbocks       https://github.com/pobocks)
;; Copyright (C) 2013-     Shin Aoyama        (@smihica      https://github.com/smihica)
;; Copyright (C) 2009-2012 Chris Done

;; Maintainer: dalu <mou.tong@qq.com>
;; URL: https://github.com/dalugm/emmet-mode
;; Version: 1.1.1
;; Keywords: convenience
;; Package-Requires: ((emacs "25.1"))

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Unfold CSS-selector-like expressions to markup.
;; Intended to be used with sgml-like languages.
;;
;; See `emmet-mode' for more information.
;;
;; Copy emmet-mode.el to your load-path and add to your .emacs:
;;
;;    (require 'emmet-mode)
;;
;; Example setup:
;;
;;    (add-to-list 'load-path "path/to/emmet-mode/")
;;    (require 'emmet-mode)
;;    ;; Auto-start on any markup modes.
;;    (add-hook 'sgml-mode-hook #'emmet-mode)
;;    (add-hook 'html-mode-hook #'emmet-mode)
;;    (add-hook 'css-mode-hook  #'emmet-mode)
;;
;; Enable the minor mode with M-x emmet-mode.
;;
;; See ``Test cases'' section for a complete set of expression types.
;;
;; If you are hacking on this project, eval (emmet-test-cases) to
;; ensure that your changes have not broken anything.
;; Feel free to add new test cases if you add new features.

;;; History:

;; This is a fork of zencoding-mode to support Emmet's feature.
;; zencoding-mode (https://github.com/rooney/zencoding)

;;; Code:

(eval-when-compile
  (require 'cl-lib)
  (require 'subr-x))

(defgroup emmet nil
  "Customization group for emmet-mode."
  :group 'convenience)

(defconst emmet-mode-version "1.1.1")

;;;; Customization.

(defcustom emmet-indentation 2
  "Number of spaces used for indentation."
  :type '(number :tag "Spaces")
  :group 'emmet)

(defcustom emmet-indent-after-insert t
  "Non-nil means indent region after insert."
  :type 'boolean
  :group 'emmet)

(defcustom emmet-use-style-tag-and-attr-detection t
  "When true, enables detection of style tags and attributes in HTML
to provide proper CSS abbreviations completion."
  :type 'boolean
  :group 'emmet)

(defcustom emmet-self-closing-tag-style "/"
  "Self-closing tags style.

This determines how Emmet expands self-closing tags.

E.g., FOO is a self-closing tag.  When expanding \"FOO\":

When \" /\", the expansion is \"<FOO />\".
When \"/\", the expansion is \"<FOO/>\".
When \"\", the expansion is \"<FOO>\".

Default value is \"/\".

NOTE: only \" /\", \"/\" and \"\" are valid."
  :type '(choice (const :tag " />" " /")
                 (const :tag "/>" "/")
                 (const :tag ">" ""))
  :group 'emmet)

(defcustom emmet-jsx-major-modes
  '(js-jsx-mode
    js-mode
    js-ts-mode
    js2-jsx-mode
    jsx-mode
    rjsx-mode
    tsx-ts-mode
    typescript-tsx-mode)
  "Major modes to use jsx class expansion."
  :type '(repeat symbol)
  :group 'emmet)

(defcustom emmet-css-major-modes
  '(css-mode
    css-ts-mode
    scss-mode
    sass-mode
    less-mode
    less-css-mode)
  "Major modes that use emmet for CSS, rather than HTML."
  :type '(repeat symbol)
  :group 'emmet)

(defcustom emmet-move-cursor-after-expanding t
  "If non-nil the the cursor position is
moved to before the first closing tag when the exp was expanded."
  :type 'boolean
  :group 'emmet)

(defcustom emmet-move-cursor-between-quotes nil
  "If emmet-move-cursor-after-expands is non-nil and this is non-nil then
cursor position will be moved to after the first quote."
  :type 'boolean
  :group 'emmet)

(defcustom emmet-expand-preview-p nil
  "If non-nil, preview the result when expand an Emmet expr."
  :type 'boolean
  :group 'emmet)

(defvar emmet-mode-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-j") #'emmet-expand-line)
    (define-key map (kbd "<C-return>") #'emmet-expand-line)
    (define-key map (kbd "<C-M-right>") #'emmet-next-edit-point)
    (define-key map (kbd "<C-M-left>") #'emmet-prev-edit-point)
    (define-key map (kbd "C-c C-c w") #'emmet-wrap-with-markup)
    map)
  "Keymap for `emmet-mode'.")

;;;; Internal variables.

(defvar emmet-leaf-function nil
  "Function to execute when expanding a leaf node in the Emmet AST.")

(defvar-local emmet-use-css-transform nil
  "If non-nil, transform Emmet snippets into CSS.")

(defvar-local emmet-use-sass-syntax nil
  "If non-nil, use Sass syntax for CSS abbreviations expanding.")

(defvar emmet-fallback-filter '("html")
  "Fallback filter for `emmet-default-filter', if none is found.")

(defvar-local emmet-file-filter nil
  "File local filter used by `emmet-default-filter'.")

;;;; Generic parsing macros and utilities.

(defmacro emmet-defparameter (symbol &optional init-value docstring)
  "Define SYMBOL with INIT-VALUE and DOCSTRING."
  `(progn
     (defvar ,symbol nil ,docstring)
     (setq   ,symbol ,init-value)))

(defmacro emmet-aif (test-form then-form &rest else-forms)
  "Anaphoric if. Temporary variable `it' is the result of TEST-FORM."
  `(let ((it ,test-form))
     (if it ,then-form ,@(or else-forms '(it)))))

(defmacro emmet-pif (test-form then-form &rest else-forms)
  "Parser anaphoric if. Temporary variable `it' is the result of TEST-FORM."
  `(let ((it ,test-form))
     (if (not (eq 'error (car it))) ,then-form ,@(or else-forms '(it)))))

(defmacro emmet-parse (regex nums label &rest body)
  "Parse according to a REGEX."
  `(emmet-aif (emmet-regex ,regex input ',(number-sequence 0 nums))
              (let ((input (elt it ,nums)))
                ,@body)
              `,`(error ,(concat "expected " ,label))))

(defmacro emmet-run (parser then-form &rest else-forms)
  "Run a PARSER and extract the parsed expression."
  `(emmet-pif (,parser input)
              (let ((input (cdr it))
                    (expr (car it)))
                ,then-form)
              ,@(or else-forms '(it))))

(defmacro emmet-por (parser1 parser2 then-form &rest else-forms)
  "OR two parsers. Try PARSER1, if it fails try PARSER2."
  `(emmet-pif (,parser1 input)
              (let ((input (cdr it))
                    (expr (car it)))
                ,then-form)
              (emmet-pif (,parser2 input)
                         (let ((input (cdr it))
                               (expr (car it)))
                           ,then-form)
                         ,@else-forms)))

(defmacro emmet-find (direction regexp &optional limit-of-search repeat-count)
  "Search REGEXP in the given DIRECTION.

Return the position (or nil) and leaving the point in place."
  `(save-excursion
     (if (,(intern (concat "re-search-" direction))
          ,regexp ,limit-of-search t ,repeat-count)
         (match-beginning 0))))

(defun emmet-string-join (lists separator)
  "Join all LISTS using SEPARATOR."
  (mapconcat #'identity lists separator))

(defun emmet-jsx-prop-value-var-p (prop-value)
  (string-match "{.+}" prop-value))

(defun emmet-regex (regexp string refs)
  "Return a list of REF matches for REGEX on STRING or nil."
  (if (string-match (concat "^" regexp "\\([^\n]*\\)$") string)
      (mapcar (lambda (ref) (match-string ref string))
              (if (sequencep refs) refs (list refs)))
    nil))

(defun emmet-find-left-bound ()
  "Find the left bound of an emmet expr."
  (save-excursion (save-match-data
                    (let ((char (char-before))
                          (in-style-attr (looking-back
                                          "style=[\"'][^\"']*"
                                          nil))
                          (syn-tab (make-syntax-table)))
                      (modify-syntax-entry ?\\ "\\")
                      (while char
                        (cond ((and in-style-attr (member char '(?\" ?\')))
                               (setq char nil))
                              ((member char '(?\} ?\] ?\)))
                               (with-syntax-table syn-tab
                                 (backward-sexp) (setq char (char-before))))
                              ((eq char ?\>)
                               (if (looking-back
                                    "<[^>]+>"
                                    (line-beginning-position))
                                   (setq char nil)
                                 (progn
                                   (backward-char)
                                   (setq char (char-before)))))
                              ((not (string-match-p
                                     "[[:space:]\n;]"
                                     (string char)))
                               (backward-char) (setq char (char-before)))
                              (t
                               (setq char nil))))
                      (point)))))

(defun emmet-expr-on-line ()
  "Extract an emmet expression and corresponding bounds for current line."
  (let* ((start (emmet-find-left-bound))
         (end (point))
         (line (buffer-substring-no-properties start end))
         (expr (emmet-regex "\\([ \t]*\\)\\([^\n]+\\)" line 2)))
    (when (cl-first expr)
      (list (cl-first expr) start end))))

(defun emmet-transform (input)
  "Transform INPUT to structured code block."
  (if (or (emmet-detect-style-tag-and-attr) emmet-use-css-transform)
      (emmet-css-transform input)
    (emmet-html-transform input)))

(defun emmet-detect-style-tag-and-attr ()
  (let ((style-attr-begin "style=[\"']")
        (style-attr-end "[^=][\"']")
        (style-tag-begin "<style.*>")
        (style-tag-end "</style>"))
    (and emmet-use-style-tag-and-attr-detection
         (or
          (emmet-check-if-between
           style-attr-begin style-attr-end) ; style attr
          (emmet-check-if-between
           style-tag-begin style-tag-end))))) ; style tag

(defun emmet-check-if-between (begin end)
  (let ((begin-back (emmet-find "backward" begin))
        (end-back (emmet-find "backward" end))
        (begin-front (emmet-find "forward" begin))
        (end-front (emmet-find "forward" end)))
    (and begin-back end-front
         (or (not end-back) (> begin-back end-back))
         (or (not begin-front) (< end-front begin-front)))))

;;;; Real-time preview.

(defvar-local emmet-preview-show-paren nil)
(defvar-local emmet-flash-ovl nil)
(defvar-local emmet-preview-input nil)
(defvar-local emmet-preview-output nil)
(defvar-local emmet-preview-pending-abort nil)

(defcustom emmet-insert-flash-time 0.5
  "Time to flash insertion.
Set this to a negative number if you do not want flashing the
expansion after insertion."
  :type '(number :tag "Seconds")
  :group 'emmet)

(defface emmet-preview-input
  '((default :box t :inherit secondary-selection))
  "Face for preview input field."
  :group 'emmet)

(defface emmet-preview-output
  '((default :inherit highlight))
  "Face for preview output field."
  :group 'emmet)

(defvar emmet-preview-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'emmet-preview-accept)
    (define-key map (kbd "<return>") #'emmet-preview-accept)
    (define-key map [(control ?g)] #'emmet-preview-abort)
    map)
  "Keymap for `emmet-preview-mode'.")

(defun emmet-html-text-p (markup)
  (string-match "^[\s|\t|\n|\r]*<.*$" markup))

(defun emmet-html-next-insert-point (str)
  (with-temp-buffer
    (insert str)
    (goto-char (point-min))
    (or
     ;; try to find an edit point
     (emmet-aif
      (emmet-go-to-edit-point 1 t)
      (- it 1))
     ;; try to place cursor after tag contents
     (emmet-aif
      (re-search-forward ".+</" nil t)
      (- it 3))
     ;; ok, just go to the end
     (length str))))

(defun emmet-css-next-insert-point (str)
  (let ((regexp (if emmet-use-sass-syntax ": *\\($\\)" ": *\\(;\\)$")))
    (save-match-data
      (set-match-data nil t)
      (string-match regexp str)
      (or (match-beginning 1) (length str)))))

(defun emmet-remove-flash-ovl (buf)
  (with-current-buffer buf
    (when (overlayp emmet-flash-ovl)
      (delete-overlay emmet-flash-ovl))
    (setq emmet-flash-ovl nil)))

(defun emmet-reposition-cursor (expr)
  (let ((output-markup
         (buffer-substring-no-properties
          (cl-second expr) (point))))
    (when emmet-move-cursor-after-expanding
      (let ((p (point))
            (new-pos (if (emmet-html-text-p output-markup)
                         (emmet-html-next-insert-point output-markup)
                       (emmet-css-next-insert-point output-markup))))
        (goto-char
         (+ (- p (length output-markup))
            new-pos))))))

(defun emmet-insert-and-flash (markup)
  (emmet-remove-flash-ovl (current-buffer))
  (let ((here (point)))
    (insert markup)
    (when emmet-indent-after-insert
      (indent-region here (point))
      (setq here
            (save-excursion
              (goto-char here)
              (skip-chars-forward "[:space:]")
              (point))))
    (setq emmet-flash-ovl (make-overlay here (point)))
    (overlay-put emmet-flash-ovl 'face 'emmet-preview-output)
    (when (< 0 emmet-insert-flash-time)
      (run-with-idle-timer
       emmet-insert-flash-time
       nil
       #'emmet-remove-flash-ovl
       (current-buffer)))))

;;;###autoload
(defun emmet-preview (beg end)
  "Expand emmet between BEG and END interactively.
This will show a preview of the expanded emmet code and you can
accept it or skip it."
  (interactive (if (use-region-p)
                   (list (region-beginning) (region-end))
                 (list nil nil)))
  (emmet-preview-abort)
  (if (not beg)
      (message "Region not active")
    (setq emmet-preview-show-paren show-paren-mode)
    (show-paren-mode -1)
    (let ((here (point)))
      (goto-char beg)
      (forward-line 1)
      (unless (= 0 (current-column))
        (insert "\n"))
      (let* ((opos (point))
             (ovli (make-overlay beg end nil nil t))
             (ovlo (make-overlay opos opos))
             (info
              (propertize
               " Emmet preview. Choose with RET. Cancel by stepping out. \n"
               'face 'tooltip)))
        (overlay-put ovli 'face 'emmet-preview-input)
        (overlay-put ovli 'keymap emmet-preview-keymap)
        (overlay-put ovlo 'face 'emmet-preview-output)
        (overlay-put ovlo 'before-string info)
        (setq emmet-preview-input  ovli)
        (setq emmet-preview-output ovlo)
        (add-hook 'before-change-functions #'emmet-preview-before-change t t)
        (goto-char here)
        (add-hook 'post-command-hook #'emmet-preview-post-command t t)))))

(defun emmet-preview-live ()
  "Display `emmet-preview' on the fly as the user types.

To use this, add the function as a local hook:

  (add-hook \\='post-self-insert-hook \\='emmet-preview-live t t)

or enable `emmet-preview-mode'."
  (ignore-errors
    (let* ((expr (emmet-expr-on-line))
           (text (nth 0 expr))
           (beg (nth 1 expr))
           (end (nth 2 expr))
           (wap (thing-at-point 'word 'no-properties)))
      (when (and (not (equal wap text))
                 (emmet-transform text))
        (emmet-preview beg end)))))

(defun emmet-preview-before-change (beg end)
  (when
      (or (> beg (overlay-end emmet-preview-input))
          (< beg (overlay-start emmet-preview-input))
          (> end (overlay-end emmet-preview-input))
          (< end (overlay-start emmet-preview-input)))
    (setq emmet-preview-pending-abort t)))

(defun emmet-preview-abort ()
  "Abort emmet code preview."
  (interactive)
  (setq emmet-preview-pending-abort nil)
  (remove-hook 'before-change-functions #'emmet-preview-before-change t)
  (when (overlayp emmet-preview-input)
    (delete-overlay emmet-preview-input))
  (setq emmet-preview-input nil)
  (when (overlayp emmet-preview-output)
    (delete-overlay emmet-preview-output))
  (setq emmet-preview-output nil)
  (remove-hook 'post-command-hook #'emmet-preview-post-command t)
  (when emmet-preview-show-paren (show-paren-mode +1)))

(defun emmet-preview-transformed ()
  "Transform preview to structured code block."
  (emmet-transform (buffer-substring-no-properties
                    (overlay-start emmet-preview-input)
                    (overlay-end emmet-preview-input))))

(defun emmet-update-preview ()
  "Update emmet preview overlay."
  (when-let* ((code (emmet-preview-transformed))
              (block (propertize code 'face 'highlight)))
    (overlay-put emmet-preview-output 'after-string
                 (concat block "\n"))))

(defun emmet-preview-accept ()
  "Accept emmet code preview."
  (interactive)
  (let ((ovli emmet-preview-input)
        (expr (emmet-expr-on-line)))
    (if (not (and (overlayp ovli)
                  (bufferp (overlay-buffer ovli))))
        (message "Preview is not active.")
      (let ((markup (emmet-preview-transformed)))
        (when markup
          (delete-region (overlay-start ovli) (overlay-end ovli))
          (emmet-insert-and-flash markup)
          (emmet-reposition-cursor expr)))))
  (emmet-preview-abort))

(defun emmet-preview-post-command ()
  (condition-case err
      (emmet-preview-post-command-1)
    (error (message "emmet-preview-post: %s" err))))

(defun emmet-preview-post-command-1 ()
  (if (and (not emmet-preview-pending-abort)
           (<= (point) (overlay-end emmet-preview-input))
           (>= (point) (overlay-start emmet-preview-input)))
      (emmet-update-preview)
    (emmet-preview-abort)))

(define-minor-mode emmet-preview-mode
  "When enabled, automatically show `emmet-preview' as the user types.

See `emmet-preview-live'."
  :init-value nil
  :group 'emmet
  (if emmet-preview-mode
      (add-hook 'post-self-insert-hook
                #'emmet-preview-live :append :local)
    (remove-hook 'post-self-insert-hook
                 #'emmet-preview-live :local)))

;;;###autoload
(defun emmet-expand-line (arg)
  "Expand current line's emmet expression.

If prefix ARG is given or region is visible call `emmet-preview'
to start an interactive preview.

Otherwise expand line directly.

For more information see `emmet-mode'."
  (interactive "P")
  (let* ((here (point))
         (preview (if emmet-expand-preview-p (not arg) arg))
         (beg (if preview
                  (emmet-find-left-bound)
                (when (use-region-p) (region-beginning))))
         (end (if preview
                  here
                (when (use-region-p) (region-end)))))
    (if (and preview beg)
        (progn
          (goto-char here)
          (emmet-preview beg end))
      (let ((expr (emmet-expr-on-line)))
        (when expr
          (let ((markup (emmet-transform (cl-first expr))))
            (when markup
              (delete-region (cl-second expr) (cl-third expr))
              (emmet-insert-and-flash markup)
              (emmet-reposition-cursor expr))))))))

;;;; Yasnippet integration.

(defun emmet-transform-yas (input)
  (let* ((leaf-count 0)
         (emmet-leaf-function
          (lambda ()
            (format "$%d" (cl-incf leaf-count)))))
    (emmet-transform input)))

;;;###autoload
(defun emmet-expand-yas ()
  (interactive)
  (let ((expr (emmet-expr-on-line)))
    (when expr
      (let* ((markup (emmet-transform-yas (cl-first expr)))
             (filled (replace-regexp-in-string "><" ">\n<" markup)))
        (delete-region (cl-second expr) (cl-third expr))
        (insert filled)
        (indent-region (cl-second expr) (point))
        (when (fboundp 'yas-expand-snippet)
          (yas-expand-snippet
           (buffer-substring (cl-second expr) (point))
           (cl-second expr) (point)))))))

;;;; Go to edit point.

(defun emmet-go-to-edit-point (count &optional only-before-closed-tag)
  "Implementation of `Go to Edit Point' functionality.

URL `https://docs.emmet.io/actions/go-to-edit-point'."
  (let* ((between-tags (if only-before-closed-tag
                           "\\(><\\)/"
                         "\\(><\\)"))
         (indented-line "\\(^[[:blank:]]+$\\)")
         (between-quotes (if emmet-move-cursor-between-quotes
                             "\\(=\\(\"\\|'\\)\\{2\\}\\)"
                           nil))
         (whole-regex
          (mapconcat 'identity
                     (delq nil
                           (list between-tags indented-line between-quotes))
                     "\\|"))
         (edit-point (format "\\(%s\\)" whole-regex)))
    (if (> count 0)
        (progn
          (forward-char)
          (let ((search-result (re-search-forward edit-point nil t count)))
            (if search-result
                (progn
                  (cond
                   ((match-string 2) (goto-char (- (match-end 2) 1)))
                   ((match-string 3) (end-of-line))
                   ((match-string 4) (backward-char)))
                  (point))
              (backward-char))))
      (progn
        (backward-char)
        (let ((search-result (re-search-backward edit-point nil t (- count))))
          (if search-result
              (progn
                (cond
                 ((match-string 2) (goto-char (- (match-end 2) 1)))
                 ((match-string 3) (end-of-line))
                 ((match-string 4) (forward-char 2)))
                (point))
            (forward-char)))))))

;;;; Wrap markup.

(defcustom emmet-postwrap-goto-edit-point nil
  "If non-nil, go to first edit point after wrapping markup."
  :type 'boolean
  :group 'emmet)

;;;###autoload
(defun emmet-wrap-with-markup (wrap-with)
  "Wrap region with markup."
  (interactive "sExpression to wrap with: ")
  (let* ((multi (string-match "\\*$" wrap-with))
         (txt (buffer-substring-no-properties
               (region-beginning)
               (region-end)))
         (to-wrap (if multi
                      (split-string txt "\n")
                    (list txt)))
         (initial-elements
          (replace-regexp-in-string
           "\\(.*\\(\\+\\|>\\)\\)?[^>*]+\\*?[[:digit:]]*$"
           "\\1" wrap-with t))
         (terminal-element
          (replace-regexp-in-string
           "\\(.*>\\)?\\([^>*]+\\)\\(\\*[[:digit:]]+$\\)?\\*?$"
           "\\2" wrap-with t))
         (multiplier-expr
          (replace-regexp-in-string
           "\\(.*>\\)?\\([^>*]+\\)\\(\\*[[:digit:]]+$\\)?\\*?$"
           "\\3" wrap-with t))
         (expr (concat
                initial-elements
                (mapconcat (lambda (el)
                             (concat terminal-element
                                     "{!!!"
                                     (secure-hash 'sha1 el)
                                     "!!!}"
                                     multiplier-expr))
                           to-wrap
                           "+")))
         (markup
          (cl-reduce
           (lambda (result text)
             (replace-regexp-in-string
              (concat "!!!" (secure-hash 'sha1 text) "!!!")
              text
              result t t))
           to-wrap
           :initial-value (emmet-transform expr))))
    (when markup
      (delete-region (region-beginning) (region-end))
      (insert markup)
      (indent-region (region-beginning) (region-end))
      (when emmet-postwrap-goto-edit-point
        (let ((end (region-end)))
          (goto-char (region-beginning))
          (unless (ignore-errors (progn (emmet-next-edit-point 1) t))
            (goto-char end)))))))

;;;###autoload
(defun emmet-next-edit-point (count)
  (interactive "^p")
  (unless (or emmet-use-css-transform (emmet-go-to-edit-point count))
    (error "Last edit point reached.")))

;;;###autoload
(defun emmet-prev-edit-point (count)
  (interactive "^p")
  (unless (or emmet-use-css-transform (emmet-go-to-edit-point (- count)))
    (error "First edit point reached.")))

(defun emmet-after-hook ()
  "Initialize Emmet's buffer-local variables."
  (when (memq major-mode emmet-css-major-modes)
    (setq emmet-use-css-transform t))
  (when (eq major-mode 'sass-mode)
    (setq emmet-use-sass-syntax t)))

;;;###autoload
(define-minor-mode emmet-mode
  "Minor mode for writing HTML and CSS markup.
With emmet for HTML and CSS you can write a line like

  ul#name>li.item*2

and have it expanded to

  <ul id=\"name\">
    <li class=\"item\"></li>
    <li class=\"item\"></li>
  </ul>

This minor mode defines keys for quick access:

\\{emmet-mode-keymap}

Home page URL `https://www.emacswiki.org/emacs/Emmet'.

See also `emmet-expand-line'."
  :lighter (" Emmet" (:eval (if emmet-preview-mode "[P]" "")))
  :keymap emmet-mode-keymap
  :after-hook (emmet-after-hook))

(provide 'emmet-mode)
