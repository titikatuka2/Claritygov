;; Proposal Timeline Tracker
;; Tracks important milestones and deadlines for governance proposals

;; Error constants
(define-constant ERR_NOT_AUTHORIZED (err u300))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u301))
(define-constant ERR_TIMELINE_EXISTS (err u302))
(define-constant ERR_MILESTONE_NOT_FOUND (err u303))
(define-constant ERR_INVALID_MILESTONE (err u304))

;; Milestone types
(define-constant MILESTONE_CREATED "created")
(define-constant MILESTONE_VOTING_STARTS "voting-starts")
(define-constant MILESTONE_VOTING_ENDS "voting-ends")
(define-constant MILESTONE_FINALIZED "finalized")
(define-constant MILESTONE_AMENDED "amended")

;; Timeline data for each proposal
(define-map proposal-timelines
  { proposal-id: uint }
  {
    proposal-type: (string-ascii 20), ;; "standard", "treasury", "amendment"
    created-block: uint,
    voting-start-block: uint,
    voting-end-block: uint,
    status: (string-ascii 20),
    milestone-count: uint
  })

;; Individual milestones for detailed tracking
(define-map proposal-milestones
  { proposal-id: uint, milestone-id: uint }
  {
    milestone-type: (string-ascii 20),
    target-block: uint,
    completed: bool,
    completed-block: (optional uint),
    description: (string-ascii 150)
  })

;; User subscriptions for deadline reminders
(define-map user-subscriptions
  { user: principal }
  { subscribed-proposals: (list 50 uint), notification-blocks: (list 10 uint) })

;; Upcoming deadlines for quick queries
(define-map upcoming-deadlines
  { timeline-date: uint }
  { proposals-ending: (list 20 uint), milestone-count: uint })

;; Track timeline statistics
(define-data-var total-timelines uint u0)
(define-data-var next-milestone-id uint u1)

;; Create timeline when proposal is created
(define-public (create-proposal-timeline (proposal-id uint) (proposal-type (string-ascii 20)) (voting-period uint))
  (let (
    (current-block stacks-block-height)
    (voting-start current-block)
    (voting-end (+ current-block voting-period))
  )
    ;; Verify proposal doesn't already have timeline
    (asserts! (is-none (map-get? proposal-timelines { proposal-id: proposal-id })) ERR_TIMELINE_EXISTS)
    
    ;; Create main timeline entry
    (map-set proposal-timelines
      { proposal-id: proposal-id }
      {
        proposal-type: proposal-type,
        created-block: current-block,
        voting-start-block: voting-start,
        voting-end-block: voting-end,
        status: "active",
        milestone-count: u0
      })
    
    ;; Create initial milestones
    (try! (add-milestone proposal-id MILESTONE_CREATED current-block "Proposal created and submitted"))
    (try! (add-milestone proposal-id MILESTONE_VOTING_STARTS voting-start "Voting period begins"))
    (try! (add-milestone proposal-id MILESTONE_VOTING_ENDS voting-end "Voting period ends - finalization required"))
    
    ;; Add to upcoming deadlines
    (try! (add-to-deadline-tracker voting-end proposal-id))
    
    ;; Update statistics
    (var-set total-timelines (+ (var-get total-timelines) u1))
    (ok true)))

;; Add a milestone to a proposal timeline
(define-private (add-milestone (proposal-id uint) (milestone-type (string-ascii 20)) (target-block uint) (description (string-ascii 150)))
  (let (
    (milestone-id (var-get next-milestone-id))
    (timeline (unwrap! (map-get? proposal-timelines { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
  )
    ;; Create milestone entry
    (map-set proposal-milestones
      { proposal-id: proposal-id, milestone-id: milestone-id }
      {
        milestone-type: milestone-type,
        target-block: target-block,
        completed: (is-eq milestone-type MILESTONE_CREATED), ;; Creation milestone is immediately completed
        completed-block: (if (is-eq milestone-type MILESTONE_CREATED) (some stacks-block-height) none),
        description: description
      })
    
    ;; Update timeline milestone count
    (map-set proposal-timelines
      { proposal-id: proposal-id }
      (merge timeline { milestone-count: (+ (get milestone-count timeline) u1) }))
    
    ;; Increment milestone counter
    (var-set next-milestone-id (+ milestone-id u1))
    (ok milestone-id)))

;; Mark milestone as completed
(define-public (complete-milestone (proposal-id uint) (milestone-id uint))
  (let (
    (milestone (unwrap! (map-get? proposal-milestones { proposal-id: proposal-id, milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
  )
    ;; Update milestone as completed
    (map-set proposal-milestones
      { proposal-id: proposal-id, milestone-id: milestone-id }
      (merge milestone {
        completed: true,
        completed-block: (some stacks-block-height)
      }))
    (ok true)))

;; Subscribe to proposal deadline notifications
(define-public (subscribe-to-proposal (proposal-id uint))
  (let (
    (current-subs (default-to { subscribed-proposals: (list), notification-blocks: (list) }
                    (map-get? user-subscriptions { user: tx-sender })))
    (proposal-list (get subscribed-proposals current-subs))
  )
    ;; Add proposal to subscription list if not already subscribed
    (if (is-none (index-of proposal-list proposal-id))
      (let ((new-list (unwrap! (as-max-len? (append proposal-list proposal-id) u50) ERR_INVALID_MILESTONE)))
        (map-set user-subscriptions
          { user: tx-sender }
          (merge current-subs { subscribed-proposals: new-list }))
        (ok true))
      (ok true)))) ;; Already subscribed

;; Add proposal to deadline tracking
(define-private (add-to-deadline-tracker (deadline-block uint) (proposal-id uint))
  (let (
    (current-deadlines (default-to { proposals-ending: (list), milestone-count: u0 }
                        (map-get? upcoming-deadlines { timeline-date: deadline-block })))
    (proposal-list (get proposals-ending current-deadlines))
  )
    (let ((new-list (unwrap! (as-max-len? (append proposal-list proposal-id) u20) ERR_INVALID_MILESTONE)))
      (map-set upcoming-deadlines
        { timeline-date: deadline-block }
        {
          proposals-ending: new-list,
          milestone-count: (+ (get milestone-count current-deadlines) u1)
        })
      (ok true))))

;; Get complete timeline for a proposal
(define-read-only (get-proposal-timeline (proposal-id uint))
  (map-get? proposal-timelines { proposal-id: proposal-id }))

;; Get specific milestone details
(define-read-only (get-milestone (proposal-id uint) (milestone-id uint))
  (map-get? proposal-milestones { proposal-id: proposal-id, milestone-id: milestone-id }))

;; Get all milestones for a proposal (up to 10)
(define-read-only (get-proposal-milestones (proposal-id uint))
  (let ((timeline (map-get? proposal-timelines { proposal-id: proposal-id })))
    (match timeline
      t (map get-milestone-by-index 
          (list proposal-id proposal-id proposal-id proposal-id proposal-id proposal-id proposal-id proposal-id proposal-id proposal-id)
          (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10))
      (list))))

;; Helper function for milestone retrieval
(define-private (get-milestone-by-index (proposal-id uint) (milestone-id uint))
  (map-get? proposal-milestones { proposal-id: proposal-id, milestone-id: milestone-id }))

;; Check if proposal has overdue milestones
(define-read-only (has-overdue-milestones (proposal-id uint))
  (let ((timeline (map-get? proposal-timelines { proposal-id: proposal-id })))
    (match timeline
      t (< stacks-block-height (get voting-end-block t))
      false)))

;; Get deadlines for a specific block
(define-read-only (get-deadlines-for-block (target-block uint))
  (map-get? upcoming-deadlines { timeline-date: target-block }))

;; Get user's subscribed proposals
(define-read-only (get-user-subscriptions (user principal))
  (map-get? user-subscriptions { user: user }))

;; Check time remaining for proposal
(define-read-only (get-time-remaining (proposal-id uint))
  (let ((timeline (map-get? proposal-timelines { proposal-id: proposal-id })))
    (match timeline
      t (let ((end-block (get voting-end-block t)))
          (if (> end-block stacks-block-height)
            (some (- end-block stacks-block-height))
            (some u0)))
      none)))

;; Get proposals ending soon (within next 1000 blocks)
(define-read-only (get-proposals-ending-soon)
  (let (
    (current-block stacks-block-height)
    (soon-block (+ current-block u1000))
  )
    (map-get? upcoming-deadlines { timeline-date: soon-block })))

;; Get timeline statistics
(define-read-only (get-timeline-stats)
  {
    total-timelines: (var-get total-timelines),
    total-milestones: (- (var-get next-milestone-id) u1),
    current-block: stacks-block-height
  })

;; Check if milestone type is valid
(define-read-only (is-valid-milestone-type (milestone-type (string-ascii 20)))
  (or (is-eq milestone-type MILESTONE_CREATED)
      (or (is-eq milestone-type MILESTONE_VOTING_STARTS)
          (or (is-eq milestone-type MILESTONE_VOTING_ENDS)
              (or (is-eq milestone-type MILESTONE_FINALIZED)
                  (is-eq milestone-type MILESTONE_AMENDED))))))

;; Get proposal status summary
(define-read-only (get-proposal-status-summary (proposal-id uint))
  (let ((timeline (map-get? proposal-timelines { proposal-id: proposal-id })))
    (match timeline
      t {
        proposal-id: proposal-id,
        status: (get status t),
        blocks-remaining: (if (> (get voting-end-block t) stacks-block-height)
                            (- (get voting-end-block t) stacks-block-height)
                            u0),
        voting-active: (and (>= stacks-block-height (get voting-start-block t))
                           (< stacks-block-height (get voting-end-block t))),
        overdue: (< (get voting-end-block t) stacks-block-height)
      }
      { proposal-id: u0, status: "not-found", blocks-remaining: u0, voting-active: false, overdue: false })))
