; commands that must be supported
; hey <person(s)>
; hey
; hey tag <id>
; hey retag <id>
; hey delete <id>
; hey data
(require-extension sql-de-lite)
(require-extension srfi-13)
(require-extension srfi-1)
(require-extension pathname-expand)
(require-extension numbers)
(require-extension json-abnf)
(require-extension json)
(require-extension uri-common)
; (require-extension mdcd)
(use loops)
(use posix)
(use listicles)
(use fmt)
(use extras)
(use utils)
(use ports)
; SET UP FUNCTIONS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CORE FUNCTIONALITY
(define (find-or-create-person name db)
	; returns (name, id) list
	; (print (sprintf "find-or-create-person ~A" name))
	(let (( id (query 
				 fetch-value 
				 (sql db "SELECT id FROM people WHERE name=? limit 1;") name)))
		(if (not (equal? id #f))
		  id
		  (create-person name db))
	  )
)

(define (create-person name db)
	(define s (prepare db "insert into people (name) values (?);"))
	(bind-parameters s name)
	(step s)
	(finalize s)
	(find-or-create-person name db)
  )
;TODO: combine find-or-create-tag with find-or-create-person
(define (find-or-create-tag name db)
	(let (( id (query 
				 fetch-value 
				 (sql db "SELECT id FROM tags WHERE name=? limit 1;") name)))
		(if (not (equal? id #f))
		  id
		  (create-tag name db))
	  )
  )
;TODO: combine create-tage with create-person
(define (create-tag name db)
	(define s (prepare db "insert into tags (name) values (?);"))
	(bind-parameters s name)
	(step s)
	(finalize s)
	(find-or-create-tag name db)
  )

(define (create-entry people db)
	; (print (sprintf "in create-entry for ~A" people))
	(let ((people-ids '()))
		(do-list name people 
			(set! people-ids (cons 
						(find-or-create-person name db)
						people-ids)))
		; we now have a list of people ids
		(create-event people-ids db)
	)
)

(define (create-event people-ids db)
	(define s (prepare db "INSERT INTO events DEFAULT VALUES"))
	(exec s)
	(let ((event-id (get-last-event-id db)))
		(do-list pid people-ids 
			(join-person-to-event pid event-id db)
		)
	)
)

(define (join-person-to-event pid eid db)
	(define s (prepare db "insert into events_people (event_id, person_id) values (?, ?);"))
	(bind-parameters s eid pid )
	(step s)
	(finalize s)
)

(define (get-last-event-id db)
	(query fetch-value (sql db "SELECT id FROM events order by id desc limit 1;"))
)

(define (find-event-by-id id db)
	; (print (sprintf "finding event by id: ~A" id))
	(query fetch-value (sql db "SELECT id FROM events where id = ?;") id)
)
(define (find-person-by-name name db)
	(query fetch-value (sql db "SELECT id FROM people where name = ?;") name))

(define (env-or-default-db-path)
	(let ((env-db (get-environment-variable "HEY_DB") ))
		; (print (sprintf "env-db: ~A    || expanded: ~A" env-db (pathname-expand env-db)))
		(if (or (not env-db) (equal? "" env-db))
			(pathname-expand "~/Dropbox/apps/hey/database/hey.db")
			(pathname-expand env-db))))

(define (get-config)
	(let (	(config-path (pathname-expand "~/.config/hey/config.json"))
			(env-db (get-environment-variable "HEY_DB") ))
		(if (file-exists? config-path) 
			; TODO: handle exception from badly formed config files
			(let ((h (pairs-list-to-hash (parser (read-all config-path)))))
				(if (or (not (hash-table-ref h "HEY_DB"))
						(equal? "" (hash-table-ref h "HEY_DB")))
					(hash-table-set! h "HEY_DB" (env-or-default-db-path)))
				h
				)
			(let ((h (make-hash-table equal?)))
				(hash-table-set! h "HEY_DB" (env-or-default-db-path))
				h
			)
		)
	)
)

(define (open-db)
	; look for it in dropbox
	; look for it in local storage location
	; if you don't find it, create it
	(let ((config (get-config)))
		(let ((hey-db (hash-table-ref config "HEY_DB")))
			; (print (sprintf "config-says db at: ~A " hey-db))
			(open-database (pathname-expand hey-db))
		)
	)
)
(define (event-has-tag? event-id tag-id db)
	(let ((count 
			 (query 
			 	 fetch-value
			 	(sql db "SELECT count(*) FROM events_tags where event_id = ? and tag_id = ?;") 
			 	event-id tag-id)))
		(> count 0))
  )
(define (join-tag-to-event tag-id event-id db)
	(if (not (event-has-tag? event-id tag-id db))
		(begin 
			(let (( s (prepare db "insert into events_tags (event_id, tag_id) values (?, ?);")))
				(bind-parameters s event-id tag-id)
				(step s)
				(finalize s)
			)
		)
	)
  )

(define (join-tags-to-event tag-ids event-id db)
	(do-list tag-id tag-ids
			 (join-tag-to-event tag-id event-id db)))

(define (tag-event tags event-id db)
    (let ((tag-ids '()))
		(do-list tag tags
			 	 (set! tag-ids (cons
			 				 	 (find-or-create-tag tag db)
			 				 	 tag-ids)))
		(join-tags-to-event tag-ids event-id db)
	)
  )
(define (comment-on-event comment-string event-id db)
			(define s (prepare db "update events set description=? where id = ?;"))
			(bind-parameters s comment-string event-id)
			(step s)
			(finalize s)
  )
(define (downcase-list items)
	(map (lambda (item) (string-downcase item)) items)
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; INSTRUCTION PARSING
(define (tag id tags)
	; (print (sprintf "asked to tag ~A with ~A" id tags))
	(let ((db (open-db)))
		(let ((event-id (find-event-by-id id db)))
			(if (not (equal? event-id #f))
			(tag-event tags id db)
			(print (sprintf "I couldn't find an event with the id ~A" id))
			)
		)
	)
  )
(define (comment id comment-string)
	; (print (sprintf "asked to tag ~A with ~A" id tags))
	(let ((db (open-db)))
		(let ((event-id (find-event-by-id id db)))
			(if (not (equal? event-id #f))
			(comment-on-event comment-string id db)
			(print (sprintf "I couldn't find an event with the id ~A" id))
			)
		)
	)
  )
(define (retag id args)
	(sprintf "asked to retag ~A with ~A" id args)
  )
; TODO: delete person and delete event are almost identical. Refactor them
(define (delete-person name)
	(let ((db (open-db)))
		(let ((person-id (find-person-by-name name db)))
			(if (not (equal? person-id #f))
				(begin
					; (print (sprintf "will delete event ~A" event-id))
					; TODO: stick this in a transaction
					(let (
						(persons-events (query fetch-all (sql db
"select e.id, 
( select count(*) from events_people  where events_people.event_id = e.id) epc
from
events e 
inner join events_people ep on ep.event_id = e.id
inner join people p on ep.person_id = p.id
where epc = 1
and p.id = ?
group by 1;"
								  ) person-id) 
								)
						( s (prepare db "delete from events_people where person_id=?;")))
						(bind-parameters s person-id)
						(step s)
						(finalize s)
						(set! s (prepare db "delete from people where id=?;"))
						(bind-parameters s person-id)
						(step s)
						(finalize s)
			 			(if (> (length persons-events) 0)
			 				(begin
			 					(let ((event-ids (map (lambda(x) (number->string (car x))) persons-events  )))
									(set! s (prepare db "delete from events where id in (?);"))
									(bind-parameters s (string-join event-ids ", "))
									(step s)
									(finalize s)
								)
							)
							(print (sprintf "found no events involving just ~A" name))
						)
					)
					(print (sprintf "~A is dead. Long live ~A!" name name))
				)
				(print (sprintf "I couldn't find a person with the name ~A" name))
			)
		)
	)
)
(define (delete-entry event-id)
	; (print (sprintf "asked to delete event ~A" event-id))
	(let ((db (open-db)))
		(let ((event-id (find-event-by-id event-id db)))
			(if (not (equal? event-id #f))
				(begin
					; (print (sprintf "will delete event ~A" event-id))
					; TODO: stick this in a transaction
					(let (( s (prepare db "delete from events_people where event_id=?;")))
						(bind-parameters s event-id)
						(step s)
						(finalize s)
						(set! s (prepare db "delete from events where id=?;"))
						(bind-parameters s event-id)
						(step s)
						(finalize s)
					)
				)
				(print (sprintf "I couldn't find an event with the id ~A" event-id))
			)
		)
	)
  )

(define (data)
	(print "asked to provide data")
  )

(define (graph args)
	(let ((known-report-types (list "people-by-hour")))
		(if (null? args)
			(print "No graph type specified. 
	Available graph types:
	* people-by-hour
  	  * A stacked bar chart of the number of interrupts, by person, by hour
    	for the past 24hrs")
			(cond 
				((equal? "people-by-hour" (car args))
					(begin ; generate the only supported graph type people-by-hour
						; TODO modify query to use this where clause 
						; once i figure out how to generate a the date at midnight yesterday
						; where e.created_at BETWEEN '2017-05-25' AND 'now'
						(let ((db (open-db)))
							(let ( 
								(db (open-db))
								(series-data '())
								(hours-hash (make-hash-table equal?))
								(person->hour->value (make-hash-table equal?))
								(previous-name "")
								(rows (query fetch-rows (sql db 
"select 
  p.name,
  strftime('%H', e.created_at) hour, count(*) interrupts
from 
  events e 
  inner join events_people ep on ep.event_id = e.id
  inner join people p on ep.person_id = p.id
group by 2, 1
order by p.name asc;"))))
; that looks like
; name | hour | interrupts
; bob  | 11   | 4
; mary | 13   | 2
;
; OR 
; ( ("bob"  11 4)
;   ("mary" 13 2))

								(do-list row rows
									(begin ; make the new hash
										;(print (sprintf "graph row: ~A - car: ~A" row (car row)))
										(let ((row-hash (make-hash-table equal?))
										  	  (person (car row))
										  	  (hour (car (cdr row)))
										  	  (interrupts (last row))
										  	  )
											(print (sprintf "person: ~A - hour: ~A interrupts: ~A" 
															person hour interrupts))
											; and the new entry
											(hash-table-set! row-hash "meta" person)
											(hash-table-set! row-hash "value" interrupts)
											(if (not (list-includes (hash-table-keys person->hour->value) person))
												(hash-table-set! person->hour->value
															 	 person
															 	 (make-hash-table equal?))
												)
											(hash-table-set! 
										  	  (hash-table-ref person->hour->value person)
										  	  hour
										  	  interrupts)
											(hash-table-set! hours-hash hour #t)
										) ; END (let ((row-hash (make-hash-table equal?))
									); END begin
								); END do-list row rows
								; OK Now we have the hashes for everyone's time
								; let's fill in the hours they don't have
								(do-list person (sort-strings< (hash-table-keys person->hour->value))
									(do-list hour (sort-strings< (hash-table-keys hours-hash))
										(let ((value (if (list-includes 
															(hash-table-keys 
																(hash-table-ref 
																	person->hour->value person))
															hour)
														(hash-table-ref 
													  	  (hash-table-ref
															person->hour->value person)
													  	  hour)
														0)))
											(let ((row-hash
													(make-hash-table equal?)))
												(hash-table-set! row-hash "meta" person)
												(hash-table-set! row-hash "value" value)
												(if (not (equal? person previous-name))
													(begin
														(set! series-data
															(append series-data
																	(list (list row-hash))))
														(set! previous-name person)
													)
													(begin 
														(let ((replacement 
														 	 	 (append (last series-data) 
																 	 	 (list row-hash))))
															(set! series-data
																(replace-nth 
																(last-index series-data) ; nth
																replacement ; replacement
																series-data)
															)
														)
													)
												)
											)
										)
									)
								)
								; data's built
								; let's generate the report
								(open-url (generate-url 
											"stacked_bar_chart"
											(sort-strings< (hash-table-keys hours-hash))
											series-data))
							); END the big let
						)
					); END people-by-hour begin...
				); END people-by-hour cond test
				(else
					(print (sprintf "Unknown report type: ~A~%Available report types: ~A" 
									(car args)
									(string-join known-report-types ", "))))
			); END of cond
		); END of if
	)
)


(define (list-events)
	(print "Recent interruptions in chronological order...\n")
	(let ((row-data '())
		  (db (open-db)))
		(do-list row (query fetch-rows (sql db 
			"SELECT e.id, e.created_at FROM events e order by e.created_at desc;"))
			; desc because the consing reverses the list. :/
			(set! row-data (cons
							 (get-event-display-data row db)
							 row-data)))
		(let ((id-column     (map (lambda(x)(sprintf "~A" (car (nth 0 x)))) row-data ))
			  (event-column  (map (lambda(x)(sprintf "~A" (nth 1 (nth 0 x)))) row-data ))
			  (people-column (map (lambda(x)(sprintf "~A" (string-join (nth 1 x) ", "))) row-data ))
			  (tags-column   (map (lambda(x)(sprintf "~A" (string-join(nth 2 x) ", "))) row-data ))
			  (row-count (length row-data)))

			(fmt #t (tabular 
					  " | " 
					  (dsp (string-join (append '("ID") id-column)  "\n")) 
					  " | " 
					  (dsp (string-join (append '("When") event-column)  "\n")) 
					  " | " 
					  (dsp (string-join (append '("Who") people-column) "\n")) 
					  " | " 
					  (dsp (string-join (append '("Tags") tags-column)   "\n" )) 
					  " | "))
		; (do-list row row-data
		; 		 (print (flatten row)))

		)
	)
)
(define (get-event-display-data event-data db)
	(let ((names (get-names-for-event (car event-data) db))
		  (tags (get-tags-for-event (car event-data) db)))
	  	(append '() (list event-data) (list names) (list tags))
	)
  )
(define (get-names-for-event eid db)
	(flatten (query fetch-rows (sql db 
			"select p.name from events e inner join events_people ep on ep.event_id = e.id inner join people p on ep.person_id = p.id where e.id=?;") eid))
  )
(define (get-tags-for-event eid db)
	(flatten (query fetch-rows (sql db 
			"select t.name from events e inner join events_tags et on et.event_id = e.id inner join tags t on et.tag_id = t.id where e.id=?;") eid))
  )

(define (process-command command args)
	; (print (sprintf "process-command args: ~A" args))
	; sometimes there's nothing passed after the command
	; in which case args is a string not a list
	; but some commands work with and without params... 
	; so we need to make sure it's always a list
	(let ((args 
			(if (not (string? args))
				args
				'(args))))
		(cond
			((equal? command "list")   (list-events))
			((equal? command "tag")    (tag          (string->number (nth 1 args)) (cdr (cdr args))))
			((equal? command "comment")(comment      (string->number (nth 1 args)) (string-join (cdr (cdr args)) " ")))
			((equal? command "retag")  (retag        (string->number (nth 1 args)) (cdr (cdr args))))
			((equal? command "delete") (delete-entry (string->number (nth 1 args))))
			((equal? command "kill")   (delete-person (nth 1 args)))
			((equal? command "data")   (data (car args)))
			((equal? command "graph")  (graph (cdr args)))
			(else (sprintf "Unknown command ~A" command))
		)
	)
  )
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; GRAPHING
(define (json->uri-string data)
	(uri-encode-string (json->string data))
)
(define (json->string data)
	(let ((output-port (open-output-string)))
		(json-write data output-port)
		(get-output-string output-port)
	)
  )
(define (generate-url graph-type labels series)
	(let (
		  (encoded-labels (json->uri-string labels))
		  (encoded-series (json->uri-string series))
		  )
	  (sprintf "http://interrupttracker.com/~A.html?labels=~A&series=~A"
		graph-type
		encoded-labels
		encoded-series)
	)
  )
(define (open-url url)
	; (print url)
	(system (sprintf "open ~A" url))
	)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define recognized-commands '("tag" "retag" "delete" "kill" "data" "list" "comment" "graph"))
(define (main args)
	; (print (sprintf "main args: ~A" args))
	(let (	(downcased-args (downcase-list args)))
		(let ((first-arg (nth 1 downcased-args)))
			(if (list-includes recognized-commands first-arg)
				(process-command first-arg (cdr downcased-args))
				(create-entry (cdr downcased-args) (open-db))
				;(sprintf "List didn't include ~A" first-arg)
			)
		)
	)
)
; exec 
(if (and (not (null? (argv))) (not (equal? (car (argv)) "csi")))
	(main (argv))
)

