;;; elmo-shimbun.el -- Shimbun interface for ELMO.

;; Copyright (C) 2001 Yuuichi Teranishi <teranisi@gohome.org>

;; Author: Yuuichi Teranishi <teranisi@gohome.org>
;; Keywords: mail, net news

;; This file is part of ELMO (Elisp Library for Message Orchestration).

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.
;;

;;; Commentary:
;; 

;;; Code:
;; 
(require 'elmo)
(require 'elmo-map)
(require 'shimbun)

(eval-and-compile
  (luna-define-class elmo-shimbun-folder
		     (elmo-map-folder) (shimbun headers header-hash group))
  (luna-define-internal-accessors 'elmo-shimbun-folder))

(luna-define-method elmo-folder-initialize ((folder
					     elmo-shimbun-folder)
					    name)
  (let ((server-group (if (string-match "\\([^.]+\\)\\." name)
			  (list (elmo-match-string 1 name)
				(substring name (match-end 0)))
			(list name))))
    (if (nth 0 server-group) ; server
	(elmo-shimbun-folder-set-shimbun-internal
	 folder
	 (shimbun-open (nth 0 server-group))))
    (if (nth 1 server-group)
	(elmo-shimbun-folder-set-group-internal
	 folder
	 (nth 1 server-group)))
    folder))

(luna-define-method elmo-folder-open-internal :before ((folder
							elmo-shimbun-folder))
  (when (elmo-folder-plugged-p folder)
    (shimbun-open-group
     (elmo-shimbun-folder-shimbun-internal folder)
     (elmo-shimbun-folder-group-internal folder))
    (elmo-shimbun-folder-set-headers-internal
     folder (shimbun-headers
	     (elmo-shimbun-folder-shimbun-internal folder)))
    (elmo-shimbun-folder-set-header-hash-internal
     folder
     (elmo-make-hash (length (elmo-shimbun-folder-headers-internal folder))))
    ;; Set up header hash.
    (dolist (header (elmo-shimbun-folder-headers-internal folder))
      (elmo-set-hash-val
       (shimbun-header-id header) header
       (elmo-shimbun-folder-header-hash-internal folder)))))

(luna-define-method elmo-folder-close-internal :after ((folder
							elmo-shimbun-folder))
  (shimbun-close-group
   (elmo-shimbun-folder-shimbun-internal folder))
  (elmo-shimbun-folder-set-headers-internal
   folder nil)
  (elmo-shimbun-folder-set-header-hash-internal
   folder nil))

(luna-define-method elmo-folder-plugged-p ((folder elmo-shimbun-folder))
  (elmo-plugged-p
   "shimbun" 
   (shimbun-server-internal (elmo-shimbun-folder-shimbun-internal folder))
   nil nil
   (shimbun-server-internal (elmo-shimbun-folder-shimbun-internal folder))))
			    
(luna-define-method elmo-folder-set-plugged ((folder elmo-shimbun-folder)
					     plugged &optional add)
  (elmo-set-plugged plugged
		    "shimbun"
		    (shimbun-server-internal
		     (elmo-shimbun-folder-shimbun-internal folder))
		    nil nil nil
		    (shimbun-server-internal
		     (elmo-shimbun-folder-shimbun-internal folder))
		    add))

(luna-define-method elmo-folder-check :after ((folder elmo-shimbun-folder))
  (when (shimbun-current-group-internal 
	 (elmo-shimbun-folder-shimbun-internal folder))
    ;; Discard current headers information.
    (elmo-folder-close-internal folder)
    (elmo-folder-open-internal folder)))

(luna-define-method elmo-folder-expand-msgdb-path ((folder
						    elmo-shimbun-folder))
  (expand-file-name
   (concat (shimbun-server-internal
	    (elmo-shimbun-folder-shimbun-internal folder))
	   "/"
	   (elmo-shimbun-folder-group-internal folder))
   (expand-file-name "shimbun" elmo-msgdb-dir)))
		     
(defun elmo-shimbun-msgdb-create-entity (folder number)
  (let ((header (elmo-get-hash-val
		 (elmo-map-message-location folder number)
		 (elmo-shimbun-folder-header-hash-internal folder))))
    (when header
      (with-temp-buffer
	(shimbun-header-insert
	 (elmo-shimbun-folder-shimbun-internal folder)
	 header)
	(elmo-msgdb-create-overview-from-buffer number)))))

(luna-define-method elmo-folder-msgdb-create ((folder elmo-shimbun-folder)
					      numlist new-mark
					      already-mark seen-mark
					      important-mark
					      seen-list)
  (let* (overview number-alist mark-alist entity
		  i percent num pair)
    (setq num (length numlist))
    (setq i 0)
    (message "Creating msgdb...")
    (while numlist
      (setq entity
	    (elmo-shimbun-msgdb-create-entity
	     folder (car numlist)))
      (when entity
	(setq overview
	      (elmo-msgdb-append-element
	       overview entity))
	(setq number-alist
	      (elmo-msgdb-number-add number-alist
				     (elmo-msgdb-overview-entity-get-number
				      entity)
				     (elmo-msgdb-overview-entity-get-id
				      entity)))
	(setq mark-alist
	      (elmo-msgdb-mark-append
	       mark-alist
	       (elmo-msgdb-overview-entity-get-number
		entity)
	       (or (elmo-msgdb-global-mark-get
		    (elmo-msgdb-overview-entity-get-id
		     entity))
		   new-mark))))
      (when (> num elmo-display-progress-threshold)
	(setq i (1+ i))
	(setq percent (/ (* i 100) num))
	(elmo-display-progress
	 'elmo-folder-msgdb-create "Creating msgdb..."
	 percent))
      (setq numlist (cdr numlist)))
    (message "Creating msgdb...done.")
    (elmo-msgdb-sort-by-date
     (list overview number-alist mark-alist))))

(luna-define-method elmo-folder-message-file-p ((folder elmo-shimbun-folder))
  nil)

(luna-define-method elmo-map-message-fetch ((folder elmo-shimbun-folder)
					    location strategy &optional
					    section outbuf unseen)
  (if outbuf
      (with-current-buffer outbuf
	(erase-buffer)
	(shimbun-article (elmo-shimbun-folder-shimbun-internal folder)
			 (elmo-get-hash-val
			  location
			  (elmo-shimbun-folder-header-hash-internal folder)))
	t)
    (with-temp-buffer
      (shimbun-article (elmo-shimbun-folder-shimbun-internal folder)
		       (elmo-get-hash-val
			location
			(elmo-shimbun-folder-header-hash-internal folder)))
      (buffer-string))))

(luna-define-method elmo-folder-list-messages-internal :around
  ((folder elmo-shimbun-folder) &optional nohide)
  (if (elmo-folder-plugged-p folder)
      (luna-call-next-method)
    t))

(luna-define-method elmo-map-folder-list-message-locations
  ((folder elmo-shimbun-folder))
  (mapcar
   (function shimbun-header-id)
   (elmo-shimbun-folder-headers-internal folder)))

(luna-define-method elmo-folder-list-subfolders ((folder elmo-shimbun-folder)
						 &optional one-level)
  (unless (elmo-shimbun-folder-group-internal folder)
    (mapcar
     (lambda (x)
       (concat (elmo-folder-prefix-internal folder)
	       (shimbun-server-internal
		(elmo-shimbun-folder-shimbun-internal folder))
	       "."
	       x))
     (shimbun-groups (elmo-shimbun-folder-shimbun-internal folder)))))

(luna-define-method elmo-folder-exists-p ((folder elmo-shimbun-folder))
  (if (elmo-shimbun-folder-group-internal folder)
      (progn
	(member 
	 (elmo-shimbun-folder-group-internal folder)
	 (shimbun-groups (elmo-shimbun-folder-shimbun-internal
			  folder))))
    t))

(luna-define-method elmo-folder-search ((folder elmo-shimbun-folder)
					condition &optional from-msgs)
  nil)

;;; To override elmo-map-folder methods.
(luna-define-method elmo-folder-list-unreads-internal
  ((folder elmo-shimbun-folder) unread-marks &optional mark-alist)
  t)

(luna-define-method elmo-folder-list-importants-internal
  ((folder elmo-shimbun-folder) important-mark)
  t)

(luna-define-method elmo-folder-unmark-important ((folder elmo-shimbun-folder)
						  numbers)
  t)

(luna-define-method elmo-folder-mark-as-important ((folder elmo-shimbun-folder)
						   numbers)
  t)

(luna-define-method elmo-folder-unmark-read ((folder elmo-shimbun-folder)
					     numbers)
  t)

(luna-define-method elmo-folder-mark-as-read ((folder elmo-shimbun-folder)
					      numbers)
  t)
  
(require 'product)
(product-provide (provide 'elmo-shimbun) (require 'elmo-version))

;;; elmo-shimbun.el ends here