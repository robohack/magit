;;; magit-submodule.el --- submodule support for Magit  -*- lexical-binding: t -*-

;; Copyright (C) 2011-2017  The Magit Project Contributors
;;
;; You should have received a copy of the AUTHORS.md file which
;; lists all contributors.  If not, see http://magit.vc/authors.

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Maintainer: Jonas Bernoulli <jonas@bernoul.li>

;; Magit is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; Magit is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Magit.  If not, see http://www.gnu.org/licenses.

;;; Code:

(require 'magit)

(defvar x-stretch-cursor)

;;; Options

(defcustom magit-submodule-list-mode-hook '(hl-line-mode)
  "Hook run after entering Magit-Submodule-List mode."
  :package-version '(magit . "2.9.0")
  :group 'magit-repolist
  :type 'hook
  :get 'magit-hook-custom-get
  :options '(hl-line-mode))

(defcustom magit-submodule-list-columns
  '(("Path"     25 magit-modulelist-column-path   nil)
    ("Version"  25 magit-repolist-column-version  nil)
    ("Branch"   20 magit-repolist-column-branch   nil)
    ("L<U" 3 magit-repolist-column-unpulled-from-upstream   ((:right-align t)))
    ("L>U" 3 magit-repolist-column-unpushed-to-upstream     ((:right-align t)))
    ("L<P" 3 magit-repolist-column-unpulled-from-pushremote ((:right-align t)))
    ("L>P" 3 magit-repolist-column-unpushed-to-pushremote   ((:right-align t))))
  "List of columns displayed by `magit-list-submodules'.

Each element has the form (HEADER WIDTH FORMAT PROPS).

HEADER is the string displayed in the header.  WIDTH is the width
of the column.  FORMAT is a function that is called with one
argument, the repository identification (usually its basename),
and with `default-directory' bound to the toplevel of its working
tree.  It has to return a string to be inserted or nil.  PROPS is
an alist that supports the keys `:right-align' and `:pad-right'."
  :package-version '(magit . "2.8.0")
  :group 'magit-repolist-mode
  :type `(repeat (list :tag "Column"
                       (string   :tag "Header Label")
                       (integer  :tag "Column Width")
                       (function :tag "Inserter Function")
                       (repeat   :tag "Properties"
                                 (list (choice :tag "Property"
                                               (const :right-align)
                                               (const :pad-right)
                                               (symbol))
                                       (sexp   :tag "Value"))))))

;;; Popup

;;;###autoload (autoload 'magit-submodule-popup "magit-submodule" nil t)
(magit-define-popup magit-submodule-popup
  "Popup console for submodule commands."
  :man-page "git-submodule"
  :switches '("Switches"
              (?N "Don't fetch new objects" "--no-fetch")  ; update
              (?R "Recursive"               "--recursive") ; update, sync
              ;; (?f "Force"                "--force")     ; add, deinit, update
              "Override all submodule.NAME.update"
              (?c "Checkout tip"    "--checkout")
              (?r "Rebase onto tip" "--rebase")
              (?m "Merge tip"       "--merge"))
  :actions
  '("Update to recorded revision(s)     Update to upstream tip(s)"
    (?u "Update one module           " magit-submodule-update)
    (?p "Pull one module             " magit-submodule-pull)
    (?U "Update all modules          " magit-submodule-update-all)
    (?P "Pull all modules            " magit-submodule-pull-all)
    "Fetch all remotes                  Fetch upstream remote(s)"
    (?f "Fetch one module's remotes  " magit-submodule-fetch-upstream)
    (?d "Fetch one module's upstream " magit-submodule-fetch)
    (?F "Fetch all modules' remotes  " magit-submodule-fetch-upstream-all)
    (?D "Fetch all modules' upstreams" magit-submodule-fetch-all)
    "Initialize module(s)               Initialize and clone module(s)"
    (?i "Initialize one module       " magit-submodule-initialize)
    (?c "Clone one module            " magit-submodule-clone)
    (?I "Initialize all modules      " magit-submodule-initialize-all)
    (?C "Clone all modules           " magit-submodule-clone-all)
    "Synchronize module(s)              Configure module(s)"
    (?s "Synchronize one module      " magit-submodule-synchronize)
    (?e "Configure one module        " magit-submodule-configure)
    (?S "Synchronize all modules     " magit-submodule-synchronize-all)
    (?E "Configure all modules       " magit-submodule-configure-all)
    "Add                                Remove"
    (?a "Add one new module          " magit-submodule-add)
    (?x "Deinit one module           " magit-submodule-deinit)
    nil
    (?r "Remove one module           " magit-submodule-remove))
  :max-action-columns 2)

;;; Commands
;;;; Update/Pull

;;;###autoload
(defun magit-submodule-update (module &rest args)
  "Update MODULE to the revision recorded in the super-project."
  (interactive
   (cons (or (magit-section-when submodule)
             (magit-read-module-path "Update module from super-repository"))
         (magit-submodule-arguments)))
  (magit-submodule--update (list module) args))

;;;###autoload
(defun magit-submodule-update-all (&rest args)
  "Update all modules to the revisions recorded in the super-project."
  (interactive (magit-submodule-arguments))
  (magit-submodule--update (magit-get-submodules) args))

;;;###autoload
(defun magit-submodule-pull (module &rest args)
  "Update MODULE to the tip of its upstream branch."
  (interactive
   (cons (or (magit-section-when submodule)
             (magit-read-module-path "Update module from upstream"))
         (magit-submodule-arguments)))
  (magit-submodule--update (list module) (cons "--remote" args)))

;;; Commands
;;;; Update/Pull

;;;###autoload
(defun magit-submodule-update (&optional init)
  "Clone missing submodules and checkout appropriate commits.
With a prefix argument also register submodules in \".git/config\"."
  (interactive "P")
  (magit-with-toplevel
    (magit-run-git-async "submodule" "update" (and init "--init"))))

;;;; Fetch

;;;###autoload
(defun magit-submodule-fetch (&optional all)
  "Fetch all submodules.
With a prefix argument fetch all remotes."
  (interactive "P")
  (magit-with-toplevel
    (magit-run-git-async "submodule" "foreach"
                         (format "git fetch %s || true" (if all "--all" "")))))

;;;; Initialize/Clone

;;;###autoload
(defun magit-submodule-init ()
  "Register submodules listed in \".gitmodules\" into \".git/config\"."
  (interactive)
  (magit-with-toplevel
    (magit-run-git-async "submodule" "init")))

;;;###autoload
(defun magit-submodule-setup ()
  "Clone and register missing submodules and checkout appropriate commits."
  (interactive)
  (magit-with-toplevel
    (--if-let (--filter (not (file-exists-p (expand-file-name ".git" it)))
                        (magit-get-submodules))
        (magit-run-git-async "submodule" "update" "--init" "--" it)
      (message "All submodules already setup"))))

;;;; Synchronize

;;;###autoload
(defun magit-submodule-sync ()
  "Update each submodule's remote URL according to \".gitmodules\"."
  (interactive)
  (magit-with-toplevel
    (magit-run-git-async "submodule" "sync")))

;;;; Add/Remove/Deinit

;;;###autoload
(defun magit-submodule-pull-all (&rest args)
  "Update all modules to the tips of their upstream branches."
  (interactive (magit-submodule-arguments))
  (magit-submodule--update (magit-get-submodules) (cons "--remote" args)))

(defun magit-submodule--update (args)
  (magit-with-toplevel
    (magit-run-git-async
     (-when-let
         (method (cond ((member "--checkout" args)
                        (setq args (delete "--checkout" args))
                        'checkout)
                       ((member "--rebase" args)
                        (setq args (delete "--rebase" args))
                        'rebase)
                       ((member "--merge" args)
                        (setq args (delete "--merge" args))
                        'merge)))
       (--mapcat (list "-c" (format "submodule.%s.update=%s"
                                    (magit-get-submodule-name it)
                                    method))
                 modules))
     "submodule" "update" args "--" modules)))

;;;; Fetch

;;;###autoload
(defun magit-submodule-fetch-upstream (module)
  "Fetch the upstream remote of MODULE."
  (interactive (list (magit-read-module-path "Fetch upstream of module")))
  (let ((default-directory (expand-file-name module (magit-toplevel))))
    (magit-run-git-async "fetch")))

;;;###autoload
(defun magit-submodule-fetch-upstream-all ()
  "Fetch the upstream remotes of all modules."
  (interactive)
  (magit-with-toplevel
    (magit-run-git-async "submodule" "foreach" "git fetch || true")))

;;;###autoload
(defun magit-submodule-fetch (module)
  "Fetch all remotes of MODULE."
  (interactive (list (magit-read-module-path "Fetch remotes of module")))
  (let ((default-directory (expand-file-name module (magit-toplevel))))
    (magit-run-git-async "fetch" "--all")))

;;;###autoload
(defun magit-submodule-fetch-all ()
  "Fetch all remotes of all modules."
  (interactive)
  (magit-with-toplevel
    (magit-run-git-async "submodule" "foreach" "git fetch --all || true")))

;;;; Initialize/Clone

;;;###autoload
(defun magit-submodule-initialize (module)
  "Register MODULE."
  (interactive (list (magit-read-module-path "Register module")))
  (let ((default-directory (expand-file-name module (magit-toplevel))))
    (magit-run-git-async "submodule" "init" "--" module)))

;;;###autoload
(defun magit-submodule-initialize-all ()
  "Register all missing modules."
  (interactive)
  (magit-with-toplevel
    (magit-run-git-async "submodule" "init")))

;;;###autoload
(defun magit-submodule-clone (module)
  "Clone and register MODULE and checkout its recorded tip."
  (interactive (list (magit-read-module-path "Clone module")))
  (let ((default-directory (expand-file-name module (magit-toplevel))))
    (if (not (file-exists-p (expand-file-name ".git")))
        (magit-run-git-async "submodule" "update" "--init" "--" module)
      (message "Module %s has already been cloned" module))))

;;;###autoload
(defun magit-submodule-clone-all ()
  "Clone and register missing modules and checkout recorded tips."
  (interactive)
  (magit-with-toplevel
    (--if-let (--filter (not (file-exists-p (expand-file-name ".git" it)))
                        (magit-get-submodules))
        (magit-run-git-async "submodule" "update" "--init" "--" it)
      (message "All modules have already been cloned"))))

;;;; Synchronize

;;;###autoload
(defun magit-submodule-synchronize (module)
  "Update MODULES remote url according to \".gitmodules\"."
  (interactive (list (magit-read-module-path "Synchronize module")))
  (let ((default-directory (expand-file-name module (magit-toplevel))))
    (magit-run-git-async "submodule" "sync" "--" module)))

;;;###autoload
(defun magit-submodule-synchronize-all ()
  "Update each module's remote url according to \".gitmodules\"."
  (interactive)
  (magit-with-toplevel
    (magit-run-git-async "submodule" "sync")))

;;;###autoload
(defun magit-submodule-configure (module)
  "Update \".gitmodules\" according to MODULE's configuration."
  (interactive (list (magit-read-module-path "Configure module")))
  )

;;;###autoload
(defun magit-submodule-configure-all (module)
  "Update \".gitmodules\" according to the configuration of all modules."
  (interactive)
  )

;;;; Add/Remove/Deinit

;;;###autoload
(defun magit-submodule-add (url &optional path name branch)
  "Add the repository at URL as a submodule.

Optional PATH is the path to the submodule relative to the root
of the superproject.  If it is nil, then the path is determined
based on the URL.

Optional NAME is the name of the submodule.  If it is nil, then
PATH also becomes the name."
  (interactive
   (magit-with-toplevel
     (let* ((url (magit-read-string-ns "Add submodule (remote url)"))
            (path (let ((read-file-name-function #'read-file-name-default))
                    (directory-file-name
                     (file-relative-name
                      (read-directory-name
                       "Add submodules at path: " nil nil nil
                       (and (string-match "\\([^./]+\\)\\(\\.git\\)?$" url)
                            (match-string 1 url))))))))
       (list url
             (directory-file-name path)
             (magit-submodule-read-name-for-path path)
             (and current-prefix-arg
                  (magit-submodule-read-branch))))))
  (magit-run-git "submodule" "add"
                 (and name (list "--name" name))
                 (and branch (list "--branch" branch))
                 ;; TODO (and ... "--force")
                 url path))

(defun magit-submodule-read-name-for-path (path)
  (setq path (directory-file-name (file-relative-name path)))
  (push (file-name-nondirectory path) minibuffer-history)
  (magit-read-string-ns
   "Submodule name" nil (cons 'minibuffer-history 2)
   (or (--keep (-let [(var val) (split-string it "=")]
                 (and (equal val path)
                      (cadr (split-string var "\\."))))
               (magit-git-lines "config" "--list" "-f" ".gitmodules"))
       path)))

;;;###autoload
(defun magit-submodule-deinit (path)
  "Unregister the module at PATH."
  (interactive
   (list (magit-completing-read "Deinit module" (magit-get-submodules)
                                nil t nil nil (magit-section-when module))))
  (magit-with-toplevel
    (magit-run-git-async "submodule" "deinit" "--" path)))

;;;###autoload
(defun magit-submodule-remove (path)
  "Remove the submodule at PATH.")

;;; Sections

;;;###autoload
(defun magit-insert-submodules ()
  "Insert sections for all modules.
For each section insert the path and the output of `git describe --tags'."
  (-when-let (modules (magit-get-submodules))
    (magit-insert-section (submodules nil t)
      (magit-insert-heading "Modules:")
      (magit-with-toplevel
        (let ((col-format (format "%%-%is " (min 25 (/ (window-width) 3)))))
          (dolist (module modules)
            (let ((default-directory
                    (expand-file-name (file-name-as-directory module))))
              (magit-insert-section (submodule module t)
                (insert (propertize (format col-format module)
                                    'face 'magit-diff-file-heading))
                (if (not (file-exists-p ".git"))
                    (insert "(uninitialized)")
                  (insert (format col-format
                                  (--if-let (magit-get-current-branch)
                                      (propertize it 'face 'magit-branch-local)
                                    (propertize "(detached)" 'face 'warning))))
                  (--when-let (magit-git-string "describe" "--tags")
                    (when (string-match-p "\\`[0-9]" it)
                      (insert ?\s))
                    (insert (propertize it 'face 'magit-tag))))
                (insert ?\n))))))
      (insert ?\n))))

(defvar magit-submodules-section-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap magit-visit-thing] 'magit-list-submodules)
    map)
  "Keymap for `submodules' sections.")

(defvar magit-submodule-section-map
  (let ((map (make-sparse-keymap)))
    (unless (featurep 'jkl)
      (define-key map "\C-j"   'magit-submodule-visit))
    (define-key map [C-return] 'magit-submodule-visit)
    (define-key map [remap magit-visit-thing]  'magit-submodule-visit)
    (define-key map [remap magit-delete-thing] 'magit-submodule-deinit)
    (define-key map "K" 'magit-file-untrack)
    (define-key map "R" 'magit-file-rename)
    map)
  "Keymap for `submodule' sections.")

(defun magit-submodule-visit (module &optional other-window)
  "Visit MODULE by calling `magit-status' on it.
Offer to initialize MODULE if it's not checked out yet.
With a prefix argument, visit in another window."
  (interactive (list (or (magit-section-when submodule)
                         (magit-read-module-path "Visit module"))
                     current-prefix-arg))
  (magit-with-toplevel
    (let ((path (expand-file-name module)))
      (if (and (not (file-exists-p (expand-file-name ".git" module)))
               (not (y-or-n-p (format "Initialize submodule '%s' first?"
                                      module))))
          (when (file-exists-p path)
            (dired-jump other-window (concat path "/.")))
        (magit-run-git-async "submodule" "update" "--init" "--" module)
        (set-process-sentinel
         magit-this-process
         (lambda (process event)
           (let ((magit-process-raise-error t))
             (magit-process-sentinel process event))
           (when (and (eq (process-status      process) 'exit)
                      (=  (process-exit-status process) 0))
             (magit-diff-visit-directory path other-window))))))))

;;;###autoload
(defun magit-insert-modules-unpulled-from-upstream ()
  "Insert sections for modules that haven't been pulled from the upstream.
These sections can be expanded to show the respective commits."
  (magit--insert-modules-logs "Modules unpulled from @{upstream}"
                              'modules-unpulled-from-upstream
                              'magit-get-upstream-ref
                              "HEAD..%s"))

;;;###autoload
(defun magit-insert-modules-unpulled-from-pushremote ()
  "Insert sections for modules that haven't been pulled from the push-remote.
These sections can be expanded to show the respective commits."
  (magit--insert-modules-logs "Modules unpulled from <push-remote>"
                              'modules-unpulled-from-pushremote
                              'magit-get-push-branch
                              "HEAD..%s"))

;;;###autoload
(defun magit-insert-modules-unpushed-to-upstream ()
  "Insert sections for modules that haven't been pushed to the upstream.
These sections can be expanded to show the respective commits."
  (magit--insert-modules-logs "Modules unmerged into @{upstream}"
                              'modules-unpushed-to-upstream
                              'magit-get-upstream-ref
                              "%s..HEAD"))

;;;###autoload
(defun magit-insert-modules-unpushed-to-pushremote ()
  "Insert sections for modules that haven't been pushed to the push-remote.
These sections can be expanded to show the respective commits."
  (magit--insert-modules-logs "Modules unpushed to <push-remote>"
                              'modules-unpushed-to-pushremote
                              'magit-get-push-branch
                              "%s..HEAD"))

(defun magit--insert-modules-logs (heading type fn format)
  "For internal use, don't add to a hook."
  (-when-let (modules (magit-get-submodules))
    (magit-insert-section section ((eval type) nil t)
      (string-match "\\`\\(.+\\) \\([^ ]+\\)\\'" heading)
      (magit-insert-heading
        (concat
         (propertize (match-string 1 heading) 'face 'magit-section-heading) " "
         (propertize (match-string 2 heading) 'face 'magit-branch-remote) ":"))
      (magit-with-toplevel
        (dolist (module modules)
          (let ((default-directory
                  (expand-file-name (file-name-as-directory module))))
            (--when-let (and (magit-file-accessible-directory-p default-directory)
                             (funcall fn))
              (magit-insert-section sec (file module t)
                (magit-insert-heading
                  (concat (propertize module 'face 'magit-diff-file-heading) ":"))
                (magit-git-wash (apply-partially 'magit-log-wash-log 'module)
                  "log" "--oneline" (format format it))
                (when (> (point) (magit-section-content sec))
                  (delete-char -1)))))))
      (if (> (point) (magit-section-content section))
          (insert ?\n)
        (magit-cancel-section)))))

;;; List

;;;###autoload
(defun magit-list-submodules ()
  "Display a list of the current repository's submodules."
  (interactive)
  (magit-display-buffer (magit-mode-get-buffer 'magit-submodule-list-mode t))
  (magit-submodule-list-mode)
  (setq tabulated-list-entries
        (mapcar (lambda (module)
                  (let ((default-directory
                          (expand-file-name (file-name-as-directory module))))
                    (list module
                          (vconcat (--map (or (funcall (nth 2 it) module) "")
                                          magit-submodule-list-columns)))))
                (magit-get-submodules)))
  (tabulated-list-print))

(defvar magit-submodule-list-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map magit-repolist-mode-map)
    (define-key map "g" 'magit-list-submodules)
    map)
  "Local keymap for Magit-Submodule-List mode buffers.")

(define-derived-mode magit-submodule-list-mode tabulated-list-mode "Modules"
  "Major mode for browsing a list of Git submodules."
  :group 'magit-repolist-mode
  (setq x-stretch-cursor        nil)
  (setq tabulated-list-padding  0)
  (setq tabulated-list-sort-key (cons "Path" nil))
  (setq tabulated-list-format
        (vconcat (mapcar (-lambda ((title width _fn props))
                           (nconc (list title width t)
                                  (-flatten props)))
                         magit-submodule-list-columns)))
  (tabulated-list-init-header))

(defun magit-modulelist-column-path (path)
  "Insert the relative path of the submodule."
  path)

(provide 'magit-submodule)
;;; magit-submodule.el ends here
