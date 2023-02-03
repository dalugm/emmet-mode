;;; emmet-mode.el --- Unofficial Emmet's support for emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2021-     Mou Tong           (@dalugm       https://github.com/dalugm)
;; Copyright (C) 2014-     Dmitry Mukhutdinov (@flyingleafe  https://github.com/flyingleafe)
;; Copyright (C) 2014-     William David Mayo (@pbocks       https://github.com/pobocks)
;; Copyright (C) 2013-     Shin Aoyama        (@smihica      https://github.com/smihica)
;; Copyright (C) 2009-2012 Chris Done

;; Maintainer: dalu <mou.tong@qq.com>
;; URL: https://github.com/dalugm/emmet-mode
;; Version: 1.0.1
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
