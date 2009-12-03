;;; ns-browse.el --- view html-enriched mail/news buffers using Netscape

;; Copyright (C) 1996, 1997 Noah S. Friedman

;; Author: Noah Friedman <friedman@splode.com>
;; Maintainer: friedman@splode.com
;; Keywords: extensions
;; Status: Works in Emacs 19 and XEmacs
;; Created: 1996-11-22

;; $Id: ns-browse.el,v 1.7 1999/03/17 07:40:27 friedman Exp $

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
;; along with this program; if not, you can either send email to this
;; program's maintainer or write to: The Free Software Foundation,
;; Inc.; 59 Temple Place, Suite 330; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Updates of this program may be available via the URL
;; http://www.splode.com/~friedman/software/emacs-lisp/

;; This program allows you view html-enriched messages contained in mail or
;; news buffers by sending them off to a currently-running Netscape browser.
;; To do so, run the command ``ns-browse-buffer'' in the mail/news article
;; buffer.  In some cases you may have to first click in that buffer if the
;; cursor isn't already there (e.g. if the cursor is currently in a summary
;; buffer.)

;; If your browser is not running on the same display as your emacs
;; process, you can use the command ``ns-browse-set-display'' to choose a
;; different display for future invocations.

;; You *must* already be running a browser.  This program will not launch
;; it for you.

;; In order for all this to work properly, you must make sure that netscape
;; recognizes some file type as "message/rfc822".  You can do this most
;; easily by putting the following line in ~/.mime.types:
;;
;;           message/rfc822      msg
;;
;; Or, if your .mimes.types file is in the new Netscape format already, use
;;
;;           ".msg" == "message/rfc822"
;;
;; The default "temporary file" used in this package to save the contents
;; of the buffer to view, ends in ".msg" but you can change this if you
;; would rather use some other extension.  Just make sure it matches the
;; message/rfc822 extension in your .mime.types file.

;; The primitives in browse-url.el are not really sufficient to handle mail
;; messages in a special way (for example, they know nothing about widening
;; hidden headers in different major modes) and I am not certain that any
;; other browsers handle email anyway.  Hence, a more specialized interface.

;; Thanks to Jamie Zawinski <jwz@netscape.com> for turning me on to
;; netscape's -remote feature.  More information about this can be found
;; via "http://home.netscape.com/newsref/std/x-remote.html".

;; NOTE: Most of this was broken in Netscape 4.0 (Communicator).
;; Mailbox window details (to be implemented):
;;
;; mailbox:/path/name		for the folder itself; URLs of this form
;; 				always get presented in the mail window.
;;
;; mailbox:/path/name?id=XXX	for a particular message (leave off
;; 				the <> around the message ID, and make
;; 				sure it's properly URL-hex-encoded).
;; 				This just returns a document of type
;; 				message/rfc822, which is then displayed
;; 				in whatever window is in use.
;;
;; mailbox:/path/name?number=37	another way of getting at it.
;;
;; mailbox:/path/name/?id=XXX&number=37	yet another way, which does some
;; 				sanity checking for the case of two msgs
;; 				having the same ID.
;;
;; Then there are a bunch of other options you can tack on there that are
;; related to display; these correspond to the menu options on the mail
;; window:
;;
;; 	headers=all		full header display
;; 	headers=some		default
;; 	headers=micro		one-line summary
;; 	headers=citation	"so-and-so wrote"
;;
;; 	part=N.N		to extract a particular sub-part of
;; 				the mime object (this returns a document
;; 				whose type is the type of the part,
;; 				rather than message/rfc822)
;;
;; 	rot13=true		frobs text/* content
;;
;; 	inline=false		turns off "display attachments inline"

;;; Code:

(defvar ns-browse-display (getenv "DISPLAY")
  "*Display where the netscape browser is currently running.
By default, it is assumed that it is running on the same display
as your emacs process.  Use ``\\[ns-browse-set-display]'' to change this.")

(defvar ns-browse-program-name "netscape"
  "*The name of the browser to invoke.")

(defvar ns-browse-keep-temporary-files nil
  "*If nil, delete temporary file after sending url to browser.
Reloading from the file will not be possible if that is done.")

(defvar ns-browse-temporary-file-template "/tmp/nsbrowse%d.msg"
  "*Template for temporary file names sent as URLs to browser.
This template is formatting with a random number \(specified as an integer\)
in an attempt to create unique file names.  Changing the template can
prevent the number from being used in the file name if you choose.
Using a unique name each time avoids caching problems, though.")

;; This variable is not a "user option" (via the lack of a `*' as the first
;; char of the doc string) because it's just too confusing for many users
;; to handle.
(defvar ns-browse-temporary-file-mode ?\600
  "Numeric permissions-mode for newly-created temporary files.

Unless you understand unix file permissions, octal notation, and
octal/decimal conversion or representation in emacs-lisp, it is probably
best to leave this variable alone; the default prohibits other users from
reading your temporary files.

For an equally unhelpful but more detailed description,
see the manual page for the `chmod' command.")

;; This function should widen the currently-narrowed region of the buffer
;; to expose all the headers associated with the current message.
;; It should return whatever state information is required to restore the
;; condition of the headers by ns-browse-hide-exposed-headers-method.
(defvar ns-browse-expose-all-headers-method
  '((rmail-mode           . ns-browse-rmail-widen-message-headers)
    (vm-mode              . ns-browse-vm-widen-message-headers)
    (vm-presentation-mode . ns-browse-vm-widen-message-headers)
    (gnus-article-mode    . ns-browse-gnus-widen-article-headers)))

;; This function should use the state information given by
;; ns-browse-expose-all-headers-method to restore the condition of the
;; mail headers (e.g. hide those not normally exposed).
(defvar ns-browse-hide-exposed-headers-method
  '((rmail-mode           . ns-browse-rmail-narrow-message-headers)
    (vm-mode              . ns-browse-vm-narrow-message-headers)
    (vm-presentation-mode . ns-browse-vm-narrow-message-headers)
    (gnus-article-mode    . ns-browse-gnus-narrow-article-headers)))


;;;###autoload
(defun ns-browse-set-display (&optional disp)
  "Set current netscape display name."
  (interactive (list (let ((s (or ns-browse-display
                                  (getenv "DISPLAY")
                                  (concat (system-name) ":0.0"))))
                       (read-from-minibuffer "Netscape DISPLAY=" s))))
  (and (string= disp "")
       (setq disp nil))
  (setq ns-browse-display disp))

;;;###autoload
(defun ns-browse-buffer (&optional buffer new-window)
  "View current buffer with netscape browser.
With prefix arg, request browser to open a new window to display
the buffer contents."
  (interactive (list nil current-prefix-arg))
  (or buffer
      (setq buffer (current-buffer)))
  (save-excursion
    (set-buffer buffer)
    (let ((data (ns-browse-expose-all-headers))
          (url (ns-browse-save-buffer-to-file buffer))
          (normal-return-p nil))
      (unwind-protect
          (setq normal-return-p (ns-browse-url url new-window))
        (ns-browse-hide-exposed-headers data)
        (ns-browse-clean-temporary-file url normal-return-p)))))

(defun ns-browse-buffer-keep (&rest args)
  (interactive)
  (let ((ns-browse-keep-temporary-files t))
    (if (interactive-p)
        (call-interactively 'ns-browse-buffer)
      (apply 'ns-browse-buffer args))))

(defun ns-browse-url (url &optional new-window)
  (let* ((errbuf (get-buffer-create "*ns-browse errors*"))
         (res nil))
    (save-excursion
      (set-buffer errbuf)
      (buffer-disable-undo errbuf)
      (erase-buffer)
      (cond ((equal (getenv "DISPLAY") ns-browse-display))
            (t
             (make-local-variable 'process-environment)
             (setq process-environment (copy-sequence process-environment))
             (setenv "DISPLAY" ns-browse-display)))
      (setq res
            (apply 'call-process ns-browse-program-name nil errbuf nil
                   (delq nil (list (and new-window "-noraise")
                                   "-remote"
                                   (format "openURL(file:%s%s)"
                                           (expand-file-name url)
                                           (if new-window ",new-window"
                                             ""))))))
      (cond ((zerop (buffer-size))
             (kill-buffer errbuf))
            (t
             (pop-to-buffer errbuf)))

      (cond ((zerop res))
            ((stringp res)
             (error "netscape got signal: %s" res))
            (t
             (error "netscape exited with exit status %d" res)))))
  ;; If we get this far without raising any exceptions, let the caller know.
  t)

(defun ns-browse-save-buffer-to-file (buffer)
  (random t)
  (let ((orig-umask (default-file-modes))
        (url (format ns-browse-temporary-file-template (random)))
        (buf (generate-new-buffer " *ns-browse*")))

    ;; If generated file name is the same as the template, then we aren't
    ;; expecting the name to be unique anyway--someone might have taken the
    ;; "%d" format specifier out.  But if it does differ, then also make
    ;; sure the file name isn't already in use.
    (or (string= url ns-browse-temporary-file-template)
        (while (file-exists-p url)
          (setq url (format ns-browse-temporary-file-template (random)))))

    (save-excursion
      (set-buffer buf)
      (insert-buffer buffer)
      (set-default-file-modes ns-browse-temporary-file-mode)
      (unwind-protect
          (write-region (point-min) (point-max) url nil 'no-message)
        (set-default-file-modes orig-umask))
      (kill-buffer buf))
    url))

(defun ns-browse-expose-all-headers ()
  (let ((method (cdr (assq major-mode ns-browse-expose-all-headers-method))))
    (and method
         (funcall method))))

(defun ns-browse-hide-exposed-headers (data)
  (let ((method (cdr (assq major-mode ns-browse-hide-exposed-headers-method))))
    (and method
         (funcall method data))))

(defsubst ns-browse-time-> (atime mtime)
  (or (> (car atime) (car mtime))
      (> (car (cdr atime)) (car (cdr mtime)))))

(defun ns-browse-clean-temporary-file (file wait-for-access-p)
  (cond (ns-browse-keep-temporary-files)
        (wait-for-access-p
         ;; I am unsure whether this is truly necessary.

         ;; It is conceivable that there might be a race condition between
         ;; the time that the "netscape -remote" command completes and the
         ;; time that the browser really loads the file, in which case we
         ;; might delete the file prematurely.  Let's assume that if the
         ;; access time of the file is more recent than the modification
         ;; time, that the browser has successfully opened it for reading
         ;; and it is safe to delete it now.
         ;; If this isn't a problem, then this loop will never iterate more
         ;; than once and all we've done is wasted a few conses.
         (let ((stat nil)
               (continue t)
               (count 5))
           (while continue
             (setq stat (file-attributes file))
             (cond ((or (zerop count)
                        (null stat)
                        (ns-browse-time-> (nth 4 stat) (nth 5 stat))
                        (not (sit-for 1)))
                    (setq continue nil)))
             (setq count (1- count)))
           (delete-file file)))
        (t
         (delete-file file))))


;; Note that these functions change the narrowed region by side effect!

;;; VM methods

;; Expose all headers of the current message, returning a marker pointing
;; to the original start of the narrowed region.
(defun ns-browse-vm-widen-message-headers ()
  (let ((beg (point-min))
        (end (point-max))
        (re-header-start "^From "))
    (goto-char (point-min))
    (widen)
    ;; In VM, if the headers are already toggled show-all, then the
    ;; envelope address is also already in view (i.e. be at point-min), so
    ;; first scan forward to the end of the message headers, then go back.
    (re-search-forward "^$" nil t)
    (cond ((re-search-backward re-header-start nil t)
           (end-of-line)
           (forward-char 1)
           (narrow-to-region (point) end)
           (set-marker (make-marker) beg))
          (t
           ;; Couldn't find start of messages; restore original region and
           ;; return nil to indicate no changes.
           (narrow-to-region beg end)
           nil))))

;; Use the saved marker to re-hide temporarily-exposed headers.
(defun ns-browse-vm-narrow-message-headers (mark)
  (and mark
       (narrow-to-region mark (point-max))))

;;; RMAIL methods

(defun ns-browse-rmail-all-headers-exposed-p ()
  (save-restriction
    (narrow-to-region (rmail-msgbeg rmail-current-message) (point-max))
    (goto-char (point-min))
    (forward-line 1)
    (= (following-char) ?0)))

(defun ns-browse-rmail-widen-message-headers ()
  (cond ((ns-browse-rmail-all-headers-exposed-p)
         'ignore)
        (t
         (rmail-toggle-header)
         'hide)))

(defun ns-browse-rmail-narrow-message-headers (action)
  (and (eq action 'hide)
       (rmail-toggle-header)))

;;; GNUS methods

(defun ns-browse-gnus-widen-article-headers ()
  (gnus-article-hide-headers -1))

(defun ns-browse-gnus-narrow-article-headers (&rest ignore)
  (gnus-article-hide-headers 1))

(provide 'ns-browse)

;;; ns-browse.el ends here
