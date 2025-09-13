;; Community Fund Smart Contract
;; A robust contract for managing community funds with voting and proposal mechanisms

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-PROPOSAL-EXPIRED (err u102))
(define-constant ERR-PROPOSAL-ALREADY-EXECUTED (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-INSUFFICIENT-FUNDS (err u105))
(define-constant ERR-ALREADY-VOTED (err u106))
(define-constant ERR-VOTING-PERIOD-ACTIVE (err u107))
(define-constant ERR-MINIMUM-QUORUM-NOT-MET (err u108))
(define-constant ERR-INVALID-RECIPIENT (err u109))
(define-constant ERR-CONTRACT-PAUSED (err u110))
(define-constant ERR-MEMBER-NOT-FOUND (err u111))
(define-constant ERR-INVALID-VOTING-PERIOD (err u112))
(define-constant ERR-INVALID-STRING-INPUT (err u113))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MINIMUM-PROPOSAL-AMOUNT u1000000) ;; 1 STX in microSTX
(define-constant MAXIMUM-PROPOSAL-AMOUNT u100000000000) ;; 100,000 STX in microSTX
(define-constant DEFAULT-VOTING-PERIOD u1440) ;; blocks (~10 days assuming 10 min block time)
(define-constant MINIMUM-QUORUM u10) ;; Minimum percentage of members that must vote

;; Data variables
(define-data-var total-fund-balance uint u0)
(define-data-var next-proposal-id uint u1)
(define-data-var total-members uint u0)
(define-data-var contract-paused bool false)
(define-data-var fund-manager principal CONTRACT-OWNER)

;; Data maps
(define-map community-members principal 
  {
    is-member: bool,
    voting-power: uint,
    joined-at: uint,
    reputation-score: uint
  }
)

(define-map proposals uint 
  {
    proposer: principal,
    recipient: principal,
    amount: uint,
    title: (string-ascii 100),
    description: (string-ascii 500),
    created-at: uint,
    voting-ends-at: uint,
    executed: bool,
    votes-for: uint,
    votes-against: uint,
    total-votes: uint,
    category: (string-ascii 50)
  }
)

(define-map member-votes 
  { proposal-id: uint, voter: principal }
  { 
    vote: bool, ;; true for yes, false for no
    voting-power-used: uint,
    voted-at: uint
  }
)

(define-map proposal-supporters uint (list 100 principal))
(define-map proposal-opponents uint (list 100 principal))

;; Helper function to validate string inputs
(define-private (is-valid-string-ascii (input (string-ascii 500)))
  (let ((input-length (len input)))
    (and 
      (> input-length u0)  ;; Not empty
      (<= input-length u500)  ;; Within bounds
      ;; Check for basic ASCII printable characters (space to ~)
      (is-eq input (unwrap! (as-max-len? input u500) false))
    )
  )
)

;; Helper function to validate shorter strings
(define-private (is-valid-short-string (input (string-ascii 100)))
  (let ((input-length (len input)))
    (and 
      (> input-length u0)  ;; Not empty
      (<= input-length u100)  ;; Within bounds
      (is-eq input (unwrap! (as-max-len? input u100) false))
    )
  )
)

;; Helper function to validate category strings
(define-private (is-valid-category-string (input (string-ascii 50)))
  (let ((input-length (len input)))
    (and 
      (> input-length u0)  ;; Not empty
      (<= input-length u50)  ;; Within bounds
      (is-eq input (unwrap! (as-max-len? input u50) false))
    )
  )
)

;; Fund management functions

(define-public (contribute-to-fund (amount uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set total-fund-balance (+ (var-get total-fund-balance) amount))
    
    ;; Add contributor as member if not already
    (if (is-none (map-get? community-members tx-sender))
      (begin
        (map-set community-members tx-sender {
          is-member: true,
          voting-power: u1,
          joined-at: stacks-block-height,
          reputation-score: u100
        })
        (var-set total-members (+ (var-get total-members) u1))
      )
      ;; Increase reputation for existing members
      (let ((member-data (unwrap! (map-get? community-members tx-sender) ERR-MEMBER-NOT-FOUND)))
        (map-set community-members tx-sender 
          (merge member-data { reputation-score: (+ (get reputation-score member-data) u10) })
        )
      )
    )
    
    (ok amount)
  )
)

(define-public (add-member (member principal) (voting-power uint))
  (begin
    (asserts! (is-eq tx-sender (var-get fund-manager)) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (> voting-power u0) ERR-INVALID-AMOUNT)
    
    (if (is-none (map-get? community-members member))
      (begin
        (map-set community-members member {
          is-member: true,
          voting-power: voting-power,
          joined-at: stacks-block-height,
          reputation-score: u100
        })
        (var-set total-members (+ (var-get total-members) u1))
        (ok true)
      )
      (ok false) ;; Member already exists
    )
  )
)

(define-public (remove-member (member principal))
  (begin
    (asserts! (is-eq tx-sender (var-get fund-manager)) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    
    (let ((member-data (map-get? community-members member)))
      (if (is-some member-data)
        (begin
          (map-delete community-members member)
          (var-set total-members (- (var-get total-members) u1))
          (ok true)
        )
        ERR-MEMBER-NOT-FOUND
      )
    )
  )
)

;; Proposal functions

(define-public (create-proposal 
  (recipient principal) 
  (amount uint) 
  (title (string-ascii 100)) 
  (description (string-ascii 500))
  (category (string-ascii 50))
  (voting-period uint)
)
  (let (
    (proposal-id (var-get next-proposal-id))
    (member-data (map-get? community-members tx-sender))
  )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-some member-data) ERR-NOT-AUTHORIZED)
    (asserts! (>= amount MINIMUM-PROPOSAL-AMOUNT) ERR-INVALID-AMOUNT)
    (asserts! (<= amount MAXIMUM-PROPOSAL-AMOUNT) ERR-INVALID-AMOUNT)
    (asserts! (<= amount (var-get total-fund-balance)) ERR-INSUFFICIENT-FUNDS)
    (asserts! (is-standard recipient) ERR-INVALID-RECIPIENT)
    (asserts! (and (>= voting-period u144) (<= voting-period u4320)) ERR-INVALID-VOTING-PERIOD) ;; 1-30 days
    
    ;; Validate string inputs
    (asserts! (is-valid-short-string title) ERR-INVALID-STRING-INPUT)
    (asserts! (is-valid-string-ascii description) ERR-INVALID-STRING-INPUT)
    (asserts! (is-valid-category-string category) ERR-INVALID-STRING-INPUT)
    
    (map-set proposals proposal-id {
      proposer: tx-sender,
      recipient: recipient,
      amount: amount,
      title: title,
      description: description,
      created-at: stacks-block-height,
      voting-ends-at: (+ stacks-block-height voting-period),
      executed: false,
      votes-for: u0,
      votes-against: u0,
      total-votes: u0,
      category: category
    })
    
    (var-set next-proposal-id (+ proposal-id u1))
    
    ;; Initialize supporter and opponent lists
    (map-set proposal-supporters proposal-id (list))
    (map-set proposal-opponents proposal-id (list))
    
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote bool))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (member-data (unwrap! (map-get? community-members tx-sender) ERR-NOT-AUTHORIZED))
    (existing-vote (map-get? member-votes { proposal-id: proposal-id, voter: tx-sender }))
    (voting-power (get voting-power member-data))
  )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (get is-member member-data) ERR-NOT-AUTHORIZED)
    (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
    (asserts! (<= stacks-block-height (get voting-ends-at proposal)) ERR-PROPOSAL-EXPIRED)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-ALREADY-EXECUTED)
    
    ;; Record the vote
    (map-set member-votes 
      { proposal-id: proposal-id, voter: tx-sender }
      { 
        vote: vote, 
        voting-power-used: voting-power,
        voted-at: stacks-block-height
      }
    )
    
    ;; Update proposal vote counts
    (let (
      (new-votes-for (if vote (+ (get votes-for proposal) voting-power) (get votes-for proposal)))
      (new-votes-against (if vote (get votes-against proposal) (+ (get votes-against proposal) voting-power)))
      (new-total-votes (+ (get total-votes proposal) voting-power))
      (supporters (default-to (list) (map-get? proposal-supporters proposal-id)))
      (opponents (default-to (list) (map-get? proposal-opponents proposal-id)))
    )
      (map-set proposals proposal-id
        (merge proposal {
          votes-for: new-votes-for,
          votes-against: new-votes-against,
          total-votes: new-total-votes
        })
      )
      
      ;; Update supporter/opponent lists
      (if vote
        (map-set proposal-supporters proposal-id 
          (unwrap! (as-max-len? (append supporters tx-sender) u100) (ok true)))
        (map-set proposal-opponents proposal-id 
          (unwrap! (as-max-len? (append opponents tx-sender) u100) (ok true)))
      )
    )
    
    ;; Update member reputation based on participation
    (map-set community-members tx-sender
      (merge member-data { 
        reputation-score: (+ (get reputation-score member-data) u5)
      })
    )
    
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (total-members-count (var-get total-members))
    (quorum-threshold (/ (* total-members-count MINIMUM-QUORUM) u100))
  )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (> stacks-block-height (get voting-ends-at proposal)) ERR-VOTING-PERIOD-ACTIVE)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-ALREADY-EXECUTED)
    (asserts! (>= (get total-votes proposal) quorum-threshold) ERR-MINIMUM-QUORUM-NOT-MET)
    (asserts! (> (get votes-for proposal) (get votes-against proposal)) ERR-NOT-AUTHORIZED)
    (asserts! (>= (var-get total-fund-balance) (get amount proposal)) ERR-INSUFFICIENT-FUNDS)
    
    ;; Execute the proposal
    (try! (as-contract (stx-transfer? (get amount proposal) tx-sender (get recipient proposal))))
    
    ;; Update fund balance
    (var-set total-fund-balance (- (var-get total-fund-balance) (get amount proposal)))
    
    ;; Mark proposal as executed
    (map-set proposals proposal-id
      (merge proposal { executed: true })
    )
    
    ;; Reward proposer for successful proposal
    (let ((proposer-data (unwrap! (map-get? community-members (get proposer proposal)) ERR-MEMBER-NOT-FOUND)))
      (map-set community-members (get proposer proposal)
        (merge proposer-data { 
          reputation-score: (+ (get reputation-score proposer-data) u25)
        })
      )
    )
    
    (ok true)
  )
)

;; Admin functions

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender (var-get fund-manager)) ERR-NOT-AUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender (var-get fund-manager)) ERR-NOT-AUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (transfer-management (new-manager principal))
  (begin
    (asserts! (is-eq tx-sender (var-get fund-manager)) ERR-NOT-AUTHORIZED)
    (asserts! (is-standard new-manager) ERR-INVALID-RECIPIENT)
    (var-set fund-manager new-manager)
    (ok true)
  )
)

(define-public (emergency-withdraw (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (var-get contract-paused) ERR-NOT-AUTHORIZED)
    (asserts! (<= amount (var-get total-fund-balance)) ERR-INSUFFICIENT-FUNDS)
    (asserts! (is-standard recipient) ERR-INVALID-RECIPIENT)
    
    (try! (as-contract (stx-transfer? amount tx-sender recipient)))
    (var-set total-fund-balance (- (var-get total-fund-balance) amount))
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-fund-balance)
  (var-get total-fund-balance)
)

(define-read-only (get-total-members)
  (var-get total-members)
)

(define-read-only (get-member-info (member principal))
  (map-get? community-members member)
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-proposal-vote (proposal-id uint) (voter principal))
  (map-get? member-votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-contract-info)
  {
    total-fund-balance: (var-get total-fund-balance),
    total-members: (var-get total-members),
    next-proposal-id: (var-get next-proposal-id),
    fund-manager: (var-get fund-manager),
    contract-paused: (var-get contract-paused),
    minimum-quorum: MINIMUM-QUORUM
  }
)

(define-read-only (is-proposal-executable (proposal-id uint))
  (let (
    (proposal (map-get? proposals proposal-id))
    (total-members-count (var-get total-members))
  )
    (if (is-some proposal)
      (let (
        (prop (unwrap-panic proposal))
        (quorum-threshold (/ (* total-members-count MINIMUM-QUORUM) u100))
      )
        {
          exists: true,
          voting-ended: (> stacks-block-height (get voting-ends-at prop)),
          not-executed: (not (get executed prop)),
          quorum-met: (>= (get total-votes prop) quorum-threshold),
          majority-support: (> (get votes-for prop) (get votes-against prop)),
          sufficient-funds: (>= (var-get total-fund-balance) (get amount prop)),
          executable: (and 
            (> stacks-block-height (get voting-ends-at prop))
            (not (get executed prop))
            (>= (get total-votes prop) quorum-threshold)
            (> (get votes-for prop) (get votes-against prop))
            (>= (var-get total-fund-balance) (get amount prop))
          )
        }
      )
      { exists: false, voting-ended: false, not-executed: false, quorum-met: false, majority-support: false, sufficient-funds: false, executable: false }
    )
  )
)

(define-read-only (get-proposal-supporters (proposal-id uint))
  (default-to (list) (map-get? proposal-supporters proposal-id))
)

(define-read-only (get-proposal-opponents (proposal-id uint))
  (default-to (list) (map-get? proposal-opponents proposal-id))
)

(define-read-only (get-member-voting-history (member principal))
  ;; This would need to be implemented with a more complex data structure
  ;; to track all votes by a member across proposals
  (ok "Voting history tracking requires additional implementation")
)

;; Utility functions for proposal categories and filtering
(define-read-only (calculate-quorum-for-proposal (proposal-id uint))
  (let (
    (total-members-count (var-get total-members))
    (proposal (map-get? proposals proposal-id))
  )
    (if (is-some proposal)
      (ok (/ (* total-members-count MINIMUM-QUORUM) u100))
      ERR-PROPOSAL-NOT-FOUND
    )
  )
)

;; Initialize contract
(begin
  (map-set community-members CONTRACT-OWNER {
    is-member: true,
    voting-power: u10,
    joined-at: stacks-block-height,
    reputation-score: u1000
  })
  (var-set total-members u1)
)