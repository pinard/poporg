;;; poporg.el --- Pop a region in a separate buffer for Org editing

;; Copyright © 2013 Ubity inc.

;; Author: François Pinard

;; This is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This pops a separate buffer for Org editing out of the contents of a comment,
;; then reinsert the modified comment in place once the edition is done.

;;; Code:

;; Variables which are only meant for popped up editing buffers.
(defvar poporg-overlay nil
  "Overlay, within the original buffer, corresponding to this edit.")
(defvar poporg-prefix nil
  "Saved prefix, meant to be reapplied to all lines when the edit ends.")
;; FIXME (make-variable-buffer-local 'poporg-overlay)
;; FIXME (make-variable-buffer-local 'poporg-prefix)

(defvar poporg-edit-buffer-name "*PopOrg*"
  "Name of the transient edit buffer for PopOrg.")

;; In each buffer, list of dimming overlays for currently edited regions.
(defvar poporg-overlays nil
  "List of overlays for all edits in the current buffer.
Right now, only one edit is allowed at a time, and this variable is global.")
;; FIXME (make-variable-buffer-local 'poporg-overlays)

(defface poporg-edited-face
  '((((class color) (background light))
     (:foreground "gray"))
    (((class color) (background dark))
     (:foreground "gray")))
  "Face for a region while it is being edited.")

(defun poporg-current-line ()
  "Return the contents of the line where the point is."
  (buffer-substring-no-properties
   (save-excursion (beginning-of-line) (point))
   (save-excursion (end-of-line) (point))))

(defun poporg-dwim ()
  (interactive)
  "Single overall command for PopOrg (a single keybinding may do it all).
Edit either the active region, the comment or string containing
the cursor, after the cursor, else before the cursor.  Within a
*PopOrg* edit buffer however, rather complete and exit the edit."
  (cond ((string-equal (buffer-name) poporg-edit-buffer-name) (poporg-edit-exit))
        ;; FIXME (and (boundp 'poporg-overlay) poporg-overlay) (poporg-edit-exit))
        ((use-region-p) (poporg-edit-region (region-beginning) (region-end)))
        ((poporg-dwim-1 (point)))
        ((poporg-dwim-1
          (let ((location (next-single-property-change (point) 'face)))
            (or location (point-max)))))
        ((and (> (point) (point-min)) (poporg-dwim-1 (1- (point)))))
        ((poporg-dwim-1
          (let ((location (previous-single-property-change (point) 'face)))
            (if (and location (> location (point-min)))
                (1- location)
              (point-min)))))
        (t (error "Nothing to edit!"))))

(defun poporg-dwim-1 (location)
  "Possibly edit the comment or string surrounding LOCATION.
The edition occurs in a separate buffer.  Return nil if nothing to edit."
  (when location
    (let ((face (get-text-property location 'face)))
      (cond ((eq face 'font-lock-comment-delimiter-face)
             (poporg-edit-comment location)
             t)
            ((eq face 'font-lock-comment-face)
             (poporg-edit-comment location)
             t)
            ((eq face 'font-lock-doc-face)
             ;; As in Emacs Lisp doc strings.
             (poporg-edit-string location)
             t)
            ((eq face 'font-lock-string-face)
             ;; As in Python doc strings.
             (poporg-edit-string location)
             t)))))

(defun poporg-edit-comment (location)
  "Discover the extent of current comment, then edit it in Org mode.
Point should be within a comment.  The edition occurs in a separate buffer."
  (require 'rebox)
  (let (start end prefix)
    (rebox-find-and-narrow)
    (setq start (point-min)
          end (point-max))
    (widen)
    (goto-char start)
    (skip-chars-backward " ")
    (setq start (point))
    ;; Set PREFIX.
    (skip-chars-forward " ")
    (skip-chars-forward comment-start)
    (skip-chars-forward " ")
    (setq prefix (buffer-substring-no-properties start (point))
          prefix-regexp (regexp-quote prefix))
    ;; Edit our extended comment.
    (poporg-edit-region start end prefix)))

(defun poporg-edit-comment-0 (location)
  "Discover the extent of current comment, then edit it in Org mode.
Point should be within a comment.  The edition occurs in a separate buffer."
  ;; FIXME: This is experimental.
  (let (start end prefix)
    (poporg-find-span '(font-lock-comment-delimiter-face
                        font-lock-comment-face))
    (goto-char start)
    (skip-chars-backward " ")
    (setq start (point))
    ;; Set PREFIX.
    (skip-chars-forward " ")
    (skip-chars-forward comment-start)
    (if (looking-at " ")
        (forward-char))
    (setq prefix (buffer-substring-no-properties start (point))
          prefix-regexp (regexp-quote prefix))
    ;; Edit our extended comment.
    (poporg-edit-region start end prefix)))

(defun poporg-edit-string (location)
  "Discover the extent of current string, then edit it in Org mode.
Point should be within a string.  The edition occurs in a separate buffer."
  ;; FIXME: This is experimental.
  (let (start end prefix)
    ;; Set END.
    (goto-char (or (next-single-property-change location 'face)
                   (point-max)))
    (skip-chars-backward "\"'\\\n")
    (when (looking-at "\n")
      (forward-char))
    (setq end (point))
    ;; Set START.
    (goto-char (or (previous-single-property-change location 'face)
                   (point-min)))
    (skip-chars-forward "\"'\\\\\n")
    (setq start (point))
    ;; Set PREFIX.
    (skip-chars-forward " ")
    (setq prefix (buffer-substring-no-properties start (point)))
    ;; Edit our string.
    (poporg-edit-region start end prefix)))

(defun poporg-edit-string-0 (location)
  "Discover the extent of current string, then edit it in Org mode.
Point should be within a string.  The edition occurs in a separate buffer."
  ;; FIXME: This is experimental.
  (let (start end prefix)
    (poporg-find-span '(font-lock-doc-face font-lock-string-face))
    ;; Set END.
    (goto-char (or (next-single-property-change location 'face)
                   (point-max)))
    (skip-chars-backward "\"'\\\n")
    (when (looking-at "\n")
      (forward-char))
    (setq end (point))
    ;; Set START.
    (goto-char (or (previous-single-property-change location 'face)
                   (point-min)))
    (skip-chars-forward "\"'\\\\\n")
    (setq start (point))
    ;; Set PREFIX.
    (skip-chars-forward " ")
    (setq prefix (buffer-substring-no-properties start (point)))
    ;; Edit our string.
    (poporg-edit-region start end prefix)))

;; FIXME: Temporary debugging code.
(defvar debug-overlay (make-overlay 1 1))
(overlay-put debug-overlay 'face 'poporg-edited-face)

(defun poporg-edit-region-0 (start end &optional minimal-prefix)
  (move-overlay debug-overlay start end (current-buffer)))

(defun poporg-edit-region (start end prefix)
  "Setup an editing buffer in Org mode with region contents from START to END.
A prefix common to all buffer lines, and to PREFIX as well, gets removed."
  (interactive "r")
  (when poporg-overlays
    (pop-to-buffer poporg-edit-buffer-name)
    (error "PopOrg already in use"))
  ;; Losely reduced out of PO mode's po-edit-string.
  (let ((start-marker (make-marker))
        (end-marker (make-marker)))
    (set-marker start-marker start)
    (set-marker end-marker end)
    (let ((buffer (current-buffer))
          ;; FIXME (edit-buffer (generate-new-buffer (concat "*" (buffer-name) "*")))
          (edit-buffer poporg-edit-buffer-name)
          (overlay (make-overlay start end))
          (string (buffer-substring start end)))
      ;; Dim and protect the original text.
      (overlay-put overlay 'face 'poporg-edited-face)
      (overlay-put overlay 'intangible t)
      (overlay-put overlay 'read-only t)
      (unless poporg-overlays
        (push 'poporg-kill-buffer-query kill-buffer-query-functions)
        (add-hook 'kill-buffer-hook 'poporg-kill-buffer-routine)
        (push overlay poporg-overlays)
        ;; Initialize a popup edit buffer.
        (pop-to-buffer edit-buffer)
        ;; FIXME (make-local-variable 'poporg-overlay)
        ;; FIXME (make-local-variable 'poporg-prefix)
        (insert string)
        (goto-char (point-min))
        (org-mode)
        (setq poporg-overlay overlay)
        ;; Reduce prefix as needed.
        (goto-char (point-min))
        (while (not (eobp))
          (setq prefix (or (fill-common-string-prefix
                            prefix (poporg-current-line))
                           ""))
          (forward-line 1))
        (setq poporg-prefix prefix)
        ;; Remove common prefix.
        (goto-char (point-min))
        (while (not (eobp))
          (delete-char (length prefix))
          (forward-line 1))))))

(defun poporg-edit-exit ()
  "Exit the edit buffer, replacing the original region."
  (interactive)
  ;; Reinsert the prefix.
  (when poporg-prefix
    (goto-char (point-min))
    (while (not (eobp))
      (insert poporg-prefix)
      (forward-line 1)))
  ;; Move everything back in place.
  (let* ((edit-buffer (current-buffer))
         (overlay poporg-overlay)
         (buffer (overlay-buffer overlay)))
    (when buffer
      (let ((string (buffer-substring-no-properties (point-min) (point-max)))
            (start (overlay-start overlay))
            (end (overlay-end overlay)))
        (with-current-buffer buffer
          (goto-char start)
          (delete-region start end)
          (insert string)))
      (unless (one-window-p)
        (delete-window)))
    (kill-buffer edit-buffer)))

(defun poporg-find-span (faces)
  "Set START and END around point, extending over text having any of FACES.
The extension goes over single newlines and their surrounding whitespace.
START and END should be already bound within the caller."
  ;; FIXME: This is experimental.
  ;; Set START.
  (save-excursion
    (goto-char (or (previous-single-property-change (point) 'face)
                   (point-min)))
    (setq start (point))
    (skip-chars-backward " ")
    (when (= (preceding-char) ?\n)
      (forward-char -1)
      (skip-chars-backward " ")
      (while (and (not (bobp))
                  (memq (get-text-property (1- (point)) 'face) comment-faces))
        (goto-char (or (previous-single-property-change (1- (point)) 'face)
                       (point-min)))
        (setq start (point))
        (skip-chars-backward " ")
        (when (= (preceding-char) ?\n)
          (forward-char -1)
          (skip-chars-backward " ")))))
  ;; Set END.
  (save-excursion
    (goto-char (or (next-single-property-change (point) 'face)
                   (point-max)))
    (setq end (point))
    (skip-chars-forward " ")
    (when (= (following-char) ?\n)
      (forward-char)
      (skip-chars-forward " ")
      (while (memq (get-text-property (point) 'face) faces)
        (goto-char (or (next-single-property-change (point) 'face)
                       (point-max)))
        (setq end (point))
        (skip-chars-forward " ")
        (when (= (following-char) ?\n)
          (forward-char)
          (skip-chars-forward " "))))))

(defun poporg-kill-buffer-query ()
  "Inhibit killing of a buffer with pending edits."
  (let ((overlays poporg-overlays)
        (value t))
    (while overlays
      (let* ((overlay (pop overlays))
             (buffer (overlay-buffer overlay)))
        (when (eq buffer (current-buffer))
          (pop-to-buffer poporg-edit-buffer-name)
          (message "First, either complete or kill this edit.")
          (setq overlays nil
                value nil))))
    value))

(defun poporg-kill-buffer-routine ()
  "Cleanup an edit buffer whenever killed."
  (when (string-equal (buffer-name) poporg-edit-buffer-name)
    (let* ((overlay poporg-overlay)
           (buffer (overlay-buffer overlay)))
      (when buffer
        (delete-overlay overlay)
        (setq poporg-overlays (delete overlay poporg-overlays))
        (unless poporg-overlays
          (setq kill-buffer-query-functions
                (delete 'poporg-kill-buffer-query kill-buffer-query-functions))
          (remove-hook 'kill-buffer-hook 'poporg-kill-buffer-routine))))))

(provide 'poporg)
  
;;; poporg.el ends here
