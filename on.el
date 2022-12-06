;;; on.el --- Hooks for faster startup -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2022 Alex Griffin
;;
;; Author: Alex Griffin <a@ajgrf.com>
;; Maintainer: Alex Griffin <a@ajgrf.com>
;; Version: 0.1.0
;; Keywords: convenience
;; Homepage: https://gitlab.com/ajgrf/on.el
;; Package-Requires: ((emacs "27.1"))
;;
;; This file is not part of GNU Emacs.
;;
;; The MIT License (MIT)
;;
;; Copyright (c) 2014-2022 Henrik Lissner.
;; Copyright (c) 2022 Alex Griffin
;;
;; Permission is hereby granted, free of charge, to any person obtaining
;; a copy of this software and associated documentation files (the
;; "Software"), to deal in the Software without restriction, including
;; without limitation the rights to use, copy, modify, merge, publish,
;; distribute, sublicense, and/or sell copies of the Software, and to
;; permit persons to whom the Software is furnished to do so, subject to
;; the following conditions:
;;
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
;; IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
;; CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
;; TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
;; SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
;;
;;; Commentary:
;;
;;  This package exposes a number of utility hooks and functions ported
;;  from Doom Emacs. The hooks make it easier to speed up Emacs startup
;;  by providing finer-grained control of the timing at which packages
;;  are loaded.
;;
;;; Code:

(defvar on-first-input-hook nil
  "Transient hooks run before the first user input.")
(put 'on-first-input-hook 'permanent-local t)

(defvar on-first-file-hook nil
  "Transient hooks run before the first interactively opened file.")
(put 'on-first-file-hook 'permanent-local t)

(defvar on-first-buffer-hook nil
  "Transient hooks run before the first interactively opened buffer.")
(put 'on-first-buffer-hook 'permanent-local t)

(defvar on-switch-buffer-hook nil
  "A list of hooks run after changing the current buffer.")

(defvar on-switch-window-hook nil
  "A list of hooks run after changing the focused windows.")

(defvar on-switch-frame-hook nil
  "A list of hooks run after changing the focused frame.")

(defvar on-init-ui-hook nil
  "List of hooks to run when the UI has been initialized.")

(defun on-run-hook-on (hook-var trigger-hooks)
  "Configure HOOK-VAR to be invoked exactly once when any of the TRIGGER-HOOKS
are invoked *after* Emacs has initialized (to reduce false positives). Once
HOOK-VAR is triggered, it is reset to nil.

HOOK-VAR is a quoted hook.
TRIGGER-HOOK is a list of quoted hooks and/or sharp-quoted functions."
  (dolist (hook trigger-hooks)
    (let ((fn (intern (format "%s-init-on-%s-h" hook-var hook))))
      (fset
       fn (lambda (&rest _)
            ;; Only trigger this after Emacs has initialized.
            (when (and after-init-time
                       (or (daemonp)
                           ;; In some cases, hooks may be lexically unset to
                           ;; inhibit them during expensive batch operations on
                           ;; buffers (such as when processing buffers
                           ;; internally). In these cases we should assume this
                           ;; hook wasn't invoked interactively.
                           (and (boundp hook)
                                (symbol-value hook))))
              (run-hooks hook-var)
              (set hook-var nil))))
      (cond ((daemonp)
             ;; In a daemon session we don't need all these lazy loading
             ;; shenanigans. Just load everything immediately.
             (add-hook 'after-init-hook fn 'append))
            ((eq hook 'find-file-hook)
             ;; Advise `after-find-file' instead of using `find-file-hook'
             ;; because the latter is triggered too late (after the file has
             ;; opened and modes are all set up).
             (advice-add 'after-find-file :before fn '((depth . -101))))
            ((add-hook hook fn -101)))
      fn)))

(defun on-run-switch-buffer-hooks-h (&optional _)
  (run-hooks 'on-switch-buffer-hook))

(defun on-run-switch-window-or-frame-hooks-h (&optional _)
  (unless (equal (old-selected-frame) (selected-frame))
    (run-hooks 'on-switch-frame-hook))
  (unless (or (minibufferp)
              (equal (old-selected-window) (minibuffer-window)))
    (run-hooks 'on-switch-window-hook)))

(defun on-init-ui-h (&optional _)
  "Initialize user interface by applying its hooks.

These should be done as late as possible, as to avoid/minimize prematurely
triggering hooks during startup."
  (run-hooks 'on-init-ui-hook)

  ;; Add trigger hooks to `on-first-buffer-hook'.
  (on-run-hook-on 'on-first-buffer-hook '(window-buffer-change-functions server-visit-hook))

  ;; Initialize `on-switch-window-hook' and `on-switch-frame-hook'
  (add-hook 'window-selection-change-functions #'on-run-switch-window-or-frame-hooks-h)
  ;; Initialize `on-switch-buffer-hook'
  (add-hook 'window-buffer-change-functions #'on-run-switch-buffer-hooks-h)
  ;; `window-buffer-change-functions' doesn't trigger for files visited via the server.
  (add-hook 'server-visit-hook #'on-run-switch-buffer-hooks-h)

  ;; Only execute this function once.
  (remove-hook 'window-buffer-change-functions #'on-init-ui-h))

;; Initialize UI as late as possible. `window-buffer-change-functions' runs
;; once, when the scratch/dashboard buffer is first displayed.
(add-hook 'window-buffer-change-functions #'on-init-ui-h -100)

(unless noninteractive
  (on-run-hook-on 'on-first-buffer-hook '(find-file-hook on-switch-buffer-hook))
  (on-run-hook-on 'on-first-file-hook   '(find-file-hook dired-initial-position-hook))
  (on-run-hook-on 'on-first-input-hook  '(pre-command-hook)))

(provide 'on)
;;; on.el ends here
