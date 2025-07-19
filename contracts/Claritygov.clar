(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_VOTED (err u102))
(define-constant ERR_VOTING_ENDED (err u103))
(define-constant ERR_VOTING_NOT_ENDED (err u104))
(define-constant ERR_PROPOSAL_NOT_ACTIVE (err u105))
(define-constant ERR_INVALID_VOTING_PERIOD (err u106))
(define-constant ERR_INSUFFICIENT_FUNDS (err u107))
(define-constant ERR_INVALID_AMOUNT (err u108))
(define-constant ERR_TREASURY_PROPOSAL_NOT_FOUND (err u109))
(define-constant ERR_ALLOCATION_NOT_FOUND (err u110))
(define-constant ERR_ALLOCATION_ALREADY_WITHDRAWN (err u111))
(define-constant ERR_NOT_ALLOCATION_RECIPIENT (err u112))
(define-constant MIN_VOTING_PERIOD u144)
(define-constant MAX_VOTING_PERIOD u4320)

(define-data-var proposal-counter uint u0)
(define-data-var min-quorum uint u100)
(define-data-var treasury-balance uint u0)
(define-data-var treasury-proposal-counter uint u0)
(define-data-var allocation-counter uint u0)

(define-map proposals
  uint
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    start-block: uint,
    end-block: uint,
    votes-for: uint,
    votes-against: uint,
    status: (string-ascii 20),
    category: (string-ascii 50)
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool, voting-power: uint }
)

(define-map voter-registry
  principal
  { registered: bool, voting-power: uint, reputation: uint }
)

(define-map proposal-votes-list
  uint
  (list 1000 principal)
)

(define-map treasury-proposals
  uint
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    amount: uint,
    recipient: principal,
    start-block: uint,
    end-block: uint,
    votes-for: uint,
    votes-against: uint,
    status: (string-ascii 20)
  }
)

(define-map treasury-votes
  { treasury-proposal-id: uint, voter: principal }
  { vote: bool, voting-power: uint }
)

(define-map fund-allocations
  uint
  {
    treasury-proposal-id: uint,
    recipient: principal,
    amount: uint,
    allocated-block: uint,
    withdrawn: bool
  }
)

(define-public (register-voter)
  (let ((caller tx-sender))
    (map-set voter-registry caller {
      registered: true,
      voting-power: u1,
      reputation: u0
    })
    (ok true)
  )
)

(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (voting-period uint) (category (string-ascii 50)))
  (let (
    (proposal-id (+ (var-get proposal-counter) u1))
    (caller tx-sender)
    (start-block stacks-block-height)
    (end-block (+ stacks-block-height voting-period))
  )
    (asserts! (is-registered caller) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= voting-period MIN_VOTING_PERIOD) (<= voting-period MAX_VOTING_PERIOD)) ERR_INVALID_VOTING_PERIOD)
    
    (map-set proposals proposal-id {
      title: title,
      description: description,
      proposer: caller,
      start-block: start-block,
      end-block: end-block,
      votes-for: u0,
      votes-against: u0,
      status: "active",
      category: category
    })
    
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

(define-public (vote (proposal-id uint) (vote-choice bool))
  (let (
    (caller tx-sender)
    (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
    (voter-info (unwrap! (map-get? voter-registry caller) ERR_NOT_AUTHORIZED))
    (voting-power (get voting-power voter-info))
  )
    (asserts! (get registered voter-info) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: caller })) ERR_ALREADY_VOTED)
    (asserts! (<= stacks-block-height (get end-block proposal)) ERR_VOTING_ENDED)
    (asserts! (is-eq (get status proposal) "active") ERR_PROPOSAL_NOT_ACTIVE)
    
    (asserts! (map-set votes { proposal-id: proposal-id, voter: caller } {
      vote: vote-choice,
      voting-power: voting-power
    }) ERR_PROPOSAL_NOT_FOUND)
    
    (begin
      (if vote-choice
        (map-set proposals proposal-id (merge proposal {
          votes-for: (+ (get votes-for proposal) voting-power)
        }))
        (map-set proposals proposal-id (merge proposal {
          votes-against: (+ (get votes-against proposal) voting-power)
        }))
      )
    )
    
    (try! (update-voter-reputation caller))
    (ok true)
  )
)

(define-public (finalize-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
    (total-votes (+ (get votes-for proposal) (get votes-against proposal)))
  )
    (asserts! (> stacks-block-height (get end-block proposal)) ERR_VOTING_NOT_ENDED)
    (asserts! (is-eq (get status proposal) "active") ERR_PROPOSAL_NOT_ACTIVE)
    
    (let ((new-status (if (and (>= total-votes (var-get min-quorum))
                              (> (get votes-for proposal) (get votes-against proposal)))
                         "passed"
                         "rejected")))
      (map-set proposals proposal-id (merge proposal { status: new-status }))
      (ok new-status)
    )
  )
)

(define-public (delegate-voting-power (delegate principal) (amount uint))
  (let (
    (caller tx-sender)
    (caller-info (unwrap! (map-get? voter-registry caller) ERR_NOT_AUTHORIZED))
    (delegate-info (default-to { registered: false, voting-power: u0, reputation: u0 }
                               (map-get? voter-registry delegate)))
  )
    (asserts! (get registered caller-info) ERR_NOT_AUTHORIZED)
    (asserts! (>= (get voting-power caller-info) amount) ERR_NOT_AUTHORIZED)
    
    (map-set voter-registry caller (merge caller-info {
      voting-power: (- (get voting-power caller-info) amount)
    }))
    
    (map-set voter-registry delegate (merge delegate-info {
      registered: true,
      voting-power: (+ (get voting-power delegate-info) amount)
    }))
    
    (ok true)
  )
)

(define-public (update-min-quorum (new-quorum uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set min-quorum new-quorum)
    (ok true)
  )
)

(define-private (update-voter-reputation (voter principal))
  (let ((voter-info (unwrap! (map-get? voter-registry voter) ERR_NOT_AUTHORIZED)))
    (map-set voter-registry voter (merge voter-info {
      reputation: (+ (get reputation voter-info) u1)
    }))
    (ok true)
  )
)

(define-private (is-registered (user principal))
  (match (map-get? voter-registry user)
    voter-info (get registered voter-info)
    false
  )
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-voter-info (voter principal))
  (map-get? voter-registry voter)
)

(define-read-only (get-proposal-count)
  (var-get proposal-counter)
)

(define-read-only (get-min-quorum)
  (var-get min-quorum)
)

(define-read-only (get-proposal-status (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (some (get status proposal))
    none
  )
)

(define-read-only (get-voting-results (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (some {
      votes-for: (get votes-for proposal),
      votes-against: (get votes-against proposal),
      total-votes: (+ (get votes-for proposal) (get votes-against proposal))
    })
    none
  )
)

(define-read-only (is-voting-active (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (and (<= stacks-block-height (get end-block proposal))
                  (is-eq (get status proposal) "active"))
    false
  )
)

(define-read-only (get-proposals-by-category (category (string-ascii 50)))
  (ok category)
)

(define-read-only (get-voter-participation (voter principal))
  (match (map-get? voter-registry voter)
    voter-info (some (get reputation voter-info))
    none
  )
)

(define-public (deposit-funds)
  (let ((amount (stx-get-balance tx-sender)))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (ok amount)
  )
)

(define-public (create-treasury-proposal (title (string-ascii 100)) (description (string-ascii 500)) (amount uint) (recipient principal) (voting-period uint))
  (let (
    (treasury-proposal-id (+ (var-get treasury-proposal-counter) u1))
    (caller tx-sender)
    (start-block stacks-block-height)
    (end-block (+ stacks-block-height voting-period))
  )
    (asserts! (is-registered caller) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= voting-period MIN_VOTING_PERIOD) (<= voting-period MAX_VOTING_PERIOD)) ERR_INVALID_VOTING_PERIOD)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (<= amount (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    (map-set treasury-proposals treasury-proposal-id {
      title: title,
      description: description,
      proposer: caller,
      amount: amount,
      recipient: recipient,
      start-block: start-block,
      end-block: end-block,
      votes-for: u0,
      votes-against: u0,
      status: "active"
    })
    
    (var-set treasury-proposal-counter treasury-proposal-id)
    (ok treasury-proposal-id)
  )
)

(define-public (vote-treasury-proposal (treasury-proposal-id uint) (vote-choice bool))
  (let (
    (caller tx-sender)
    (treasury-proposal (unwrap! (map-get? treasury-proposals treasury-proposal-id) ERR_TREASURY_PROPOSAL_NOT_FOUND))
    (voter-info (unwrap! (map-get? voter-registry caller) ERR_NOT_AUTHORIZED))
    (voting-power (get voting-power voter-info))
  )
    (asserts! (get registered voter-info) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (map-get? treasury-votes { treasury-proposal-id: treasury-proposal-id, voter: caller })) ERR_ALREADY_VOTED)
    (asserts! (<= stacks-block-height (get end-block treasury-proposal)) ERR_VOTING_ENDED)
    (asserts! (is-eq (get status treasury-proposal) "active") ERR_PROPOSAL_NOT_ACTIVE)
    
    (asserts! (map-set treasury-votes { treasury-proposal-id: treasury-proposal-id, voter: caller } {
      vote: vote-choice,
      voting-power: voting-power
    }) ERR_TREASURY_PROPOSAL_NOT_FOUND)
    
    (begin
      (if vote-choice
        (map-set treasury-proposals treasury-proposal-id (merge treasury-proposal {
          votes-for: (+ (get votes-for treasury-proposal) voting-power)
        }))
        (map-set treasury-proposals treasury-proposal-id (merge treasury-proposal {
          votes-against: (+ (get votes-against treasury-proposal) voting-power)
        }))
      )
    )
    
    (try! (update-voter-reputation caller))
    (ok true)
  )
)

(define-public (finalize-treasury-proposal (treasury-proposal-id uint))
  (let (
    (treasury-proposal (unwrap! (map-get? treasury-proposals treasury-proposal-id) ERR_TREASURY_PROPOSAL_NOT_FOUND))
    (total-votes (+ (get votes-for treasury-proposal) (get votes-against treasury-proposal)))
  )
    (asserts! (> stacks-block-height (get end-block treasury-proposal)) ERR_VOTING_NOT_ENDED)
    (asserts! (is-eq (get status treasury-proposal) "active") ERR_PROPOSAL_NOT_ACTIVE)
    
    (let ((proposal-passed (and (>= total-votes (var-get min-quorum))
                               (> (get votes-for treasury-proposal) (get votes-against treasury-proposal)))))
      (if proposal-passed
        (begin
          (map-set treasury-proposals treasury-proposal-id (merge treasury-proposal { status: "passed" }))
          (try! (allocate-funds treasury-proposal-id))
          (ok "passed")
        )
        (begin
          (map-set treasury-proposals treasury-proposal-id (merge treasury-proposal { status: "rejected" }))
          (ok "rejected")
        )
      )
    )
  )
)

(define-private (allocate-funds (treasury-proposal-id uint))
  (let (
    (treasury-proposal (unwrap! (map-get? treasury-proposals treasury-proposal-id) ERR_TREASURY_PROPOSAL_NOT_FOUND))
    (allocation-id (+ (var-get allocation-counter) u1))
    (amount (get amount treasury-proposal))
    (recipient (get recipient treasury-proposal))
  )
    (asserts! (<= amount (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    (map-set fund-allocations allocation-id {
      treasury-proposal-id: treasury-proposal-id,
      recipient: recipient,
      amount: amount,
      allocated-block: stacks-block-height,
      withdrawn: false
    })
    
    (var-set allocation-counter allocation-id)
    (var-set treasury-balance (- (var-get treasury-balance) amount))
    (ok allocation-id)
  )
)

(define-public (withdraw-allocated-funds (allocation-id uint))
  (let (
    (allocation (unwrap! (map-get? fund-allocations allocation-id) ERR_ALLOCATION_NOT_FOUND))
    (caller tx-sender)
  )
    (asserts! (is-eq caller (get recipient allocation)) ERR_NOT_ALLOCATION_RECIPIENT)
    (asserts! (not (get withdrawn allocation)) ERR_ALLOCATION_ALREADY_WITHDRAWN)
    
    (try! (as-contract (stx-transfer? (get amount allocation) tx-sender caller)))
    (map-set fund-allocations allocation-id (merge allocation { withdrawn: true }))
    (ok true)
  )
)

(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

(define-read-only (get-treasury-proposal (treasury-proposal-id uint))
  (map-get? treasury-proposals treasury-proposal-id)
)

(define-read-only (get-treasury-proposal-count)
  (var-get treasury-proposal-counter)
)

(define-read-only (get-treasury-vote (treasury-proposal-id uint) (voter principal))
  (map-get? treasury-votes { treasury-proposal-id: treasury-proposal-id, voter: voter })
)

(define-read-only (get-fund-allocation (allocation-id uint))
  (map-get? fund-allocations allocation-id)
)

(define-read-only (get-allocation-count)
  (var-get allocation-counter)
)

(define-read-only (get-treasury-proposal-results (treasury-proposal-id uint))
  (match (map-get? treasury-proposals treasury-proposal-id)
    treasury-proposal (some {
      votes-for: (get votes-for treasury-proposal),
      votes-against: (get votes-against treasury-proposal),
      total-votes: (+ (get votes-for treasury-proposal) (get votes-against treasury-proposal))
    })
    none
  )
)

(define-read-only (is-treasury-voting-active (treasury-proposal-id uint))
  (match (map-get? treasury-proposals treasury-proposal-id)
    treasury-proposal (and (<= stacks-block-height (get end-block treasury-proposal))
                          (is-eq (get status treasury-proposal) "active"))
    false
  )
)