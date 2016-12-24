;;; org-category-capture.el --- Tools for the contextual capture of org-mode TODOs. -*- lexical-binding: t; -*-

;; Copyright (C) 2016 Ivan Malison

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package aims to provide an easy interface to creating per
;; project org-mode TODO headings.

;;; Code:

(require 'cl-lib)
(require 'eieio)
(require 'org)
(require 'org-capture)
;; XXX: dired-buffers is used below
(require 'dired)

(defclass occ-strategy ()
  ())

(defmethod occ-get-categories ((_ occ-strategy)))

(defmethod occ-get-todo-files ((_ occ-strategy)))

(defmethod occ-get-capture-file ((_ occ-strategy) category)
  category)

(defmethod occ-get-capture-marker ((_ occ-strategy) context)
  "Return a marker that corresponds to the capture location for CONTEXT."
  context)

(defmethod occ-target-entry-p ((_ occ-strategy) context)
  (when context t))

(defclass occ-context ()
  ((category :initarg :category)
   (template :initarg :template)
   (options :initarg :options)
   (strategy :initarg :strategy)))

(defmethod occ-build-capture-template
  ((context occ-context) &rest args)
  (apply 'occ-build-capture-template-emacs-24-hack context args))

;; This is needed becaused cl-defmethod doesn't exist in emacs24
(cl-defun occ-build-capture-template-emacs-24-hack
    (context &key (character "p") (heading "Category TODO"))
  (with-slots (template options strategy) context
    (apply 'list character heading 'entry
           (list 'function (apply-partially 'occ-get-capture-location strategy context))
           template options)))

(defmethod occ-capture ((context occ-context))
  (with-slots (category template options strategy)
      context
    (org-capture-set-plist (occ-build-capture-template context))
    ;; TODO/XXX: super gross that this had to be copied from org-capture,
    ;; Unfortunately, it does not seem to be possible to call into org-capture
    ;; because it makes assumptions that make it impossible to set things up
    ;; properly. Specifically, the business logic of `org-capture' is tightly
    ;; coupled to the UI/user interactions that usually take place.
    (let ((orig-buf (current-buffer))
          (annotation (if (and (boundp 'org-capture-link-is-already-stored)
                               org-capture-link-is-already-stored)
                          (plist-get org-store-link-plist :annotation)
                        (ignore-errors (org-store-link nil)))))
      (org-capture-put :original-buffer orig-buf
                       :original-file (or (buffer-file-name orig-buf)
                                          (and (featurep 'dired)
                                               (car (rassq orig-buf dired-buffers))))
                       :original-file-nondirectory
                       (and (buffer-file-name orig-buf)
                            (file-name-nondirectory
                             (buffer-file-name orig-buf)))
                       :annotation annotation
                       :initial ""
                       :return-to-wconf (current-window-configuration)
                       :default-time
                       (or org-overriding-default-time
                           (org-current-time)))
      (org-capture-put :template (org-capture-fill-template template))
      (org-capture-set-target-location
       (list 'function (lambda ()
                         (occ-capture-goto-marker context))))
      (org-capture-put :target-entry-p (occ-target-entry-p strategy context))
      (org-capture-place-template))))

(defun occ-capture-goto-marker (context)
  (let ((marker (occ-get-capture-marker context)))
    (switch-to-buffer (marker-buffer marker))
    (goto-char (marker-position marker))))

(defmethod occ-get-capture-marker ((context occ-context))
  (occ-get-capture-marker (oref context strategy) context))

(cl-defun occ-goto-category-heading
    (category &key (transformers '(identity)) (level 1)
              (min (point-min)) (max (point-max)) &allow-other-keys)
  "Find a heading with text CATEGORY (optionally transformed by TRANSFORMERS).

If LEVEL is non-nil only headings at that level will be provided.
If MIN is provided goto min before starting the search. The
search will be bounded by MAX."
  (or (cl-loop for fn in transformers
           do (goto-char min)
           for result = (occ-find-heading-at-level
                         (funcall fn category) level max)
           when result return result)
      ;; Go back to the original point if we find nothing
      (progn (goto-char min) nil)))

(defun occ-find-heading-at-level (heading level max)
  (let ((regexp (format org-complex-heading-regexp-format heading)))
    (cl-loop for result = (re-search-forward regexp max t)
             unless result return result
             when (or (not level) (equal (org-current-level) level))
             return result)))

(cl-defun occ-goto-or-insert-category-heading
    (category &rest args &key (build-heading 'identity)
              (insert-heading-fn (apply-partially 'org-insert-heading t t t))
              &allow-other-keys)
  "Create a heading for CATEGORY unless one is found with `occ-goto-category-heading'.

BUILD-HEADING will be applied to category to create the heading
text. INSERT-HEADING-FN is the function that will be used to
create the new bullet for the category heading. This function is
tuned so that by default it looks and creates top level headings."
  (unless (apply 'occ-goto-category-heading category args)
    (org-end-of-line)
    (funcall insert-heading-fn)
    (org-set-property "CATEGORY" category)
    (insert (funcall build-heading category))))

(defun occ-goto-or-insert-category-heading-subtree (category &rest args)
  "Call `occ-goto-or-insert-category-heading' with CATEGORY forwarding ARGS.

Provide arguments that will make it consider subheadings of the
current heading."
  (apply 'occ-goto-or-insert-category-heading
         category :insert-heading-fn (apply-partially 'org-insert-subheading t)
         :level (1+ (org-current-level)) :min (point)
         :max (save-excursion (org-end-of-subtree) (point))
         args))

(provide 'org-category-capture)
;;; org-category-capture.el ends here
