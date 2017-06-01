;;;; interrupt-database.import.scm - GENERATED BY CHICKEN 4.11.0 -*- Scheme -*-

(eval '(import chicken scheme sql-de-lite loops))
(##sys#register-compiled-module
  'interrupt-database
  (list)
  '((find-id-of-person . interrupt-database#find-id-of-person)
    (find-id-of-tag . interrupt-database#find-id-of-tag)
    (create-person . interrupt-database#create-person)
    (create-tag . interrupt-database#create-tag)
    (create-event . interrupt-database#create-event)
    (get-last-event-id . interrupt-database#get-last-event-id)
    (join-person-to-event . interrupt-database#join-person-to-event))
  (list)
  (list))

;; END OF FILE
