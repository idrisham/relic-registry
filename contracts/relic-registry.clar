;; Relic Registry: Authenticated Custodianship Protocol Contract
;;
;; This smart contract implements a secure blockchain-based system for storing, managing, and verifying critical legal documents with granular access control.
;; It allows users to upload, share, update, and verify digital archives while maintaining ownership records and access permissions in a decentralized manner.

;; ====================================================================================
;; Storage Definitions
;; ====================================================================================

;; Master count of all registered archives
(define-data-var archive-registry-size uint u0)

;; Primary storage for digital archives
(define-map digital-archives
  { archive-id: uint }
  {
    archive-name: (string-ascii 64),
    archive-steward: principal,
    archive-dimensions: uint,
    registration-timestamp: uint,
    archive-summary: (string-ascii 128),
    archive-classifications: (list 10 (string-ascii 32))
  }
)

;; Access control registry for archives
(define-map archive-access-registry
  { archive-id: uint, accessor: principal }
  { access-granted: bool }
)

;; Verification registry for authenticated assessments
(define-map archive-authentication-registry
  { archive-id: uint }
  {
    authentication-status: bool,
    authenticated-by: principal,
    authentication-timestamp: uint,
    examiner-notes: (string-ascii 256)
  }
)

;; Registry of authorized examiners
(define-map authorized-examiners
  { examiner: principal }
  { authorization-status: bool }
)

;; ====================================================================================
;; Configuration and Constants
;; ====================================================================================

;; System Administrator (contract deployer)
(define-constant system-curator tx-sender)

;; Response Status Codes
(define-constant err-admin-restricted (err u300))
(define-constant err-archive-not-found (err u301))
(define-constant err-duplicate-archive (err u302))
(define-constant err-invalid-archive-name (err u303))
(define-constant err-invalid-archive-dimensions (err u304))
(define-constant err-access-violation (err u305))
(define-constant err-operation-forbidden (err u306))
(define-constant err-viewing-restriction (err u307))
(define-constant err-invalid-classification (err u308))

;; ====================================================================================
;; Private Utility Functions
;; ====================================================================================

;; Determines if archive exists in registry
(define-private (archive-exists? (archive-id uint))
  (is-some (map-get? digital-archives { archive-id: archive-id }))
)

;; Retrieves dimensions of specified archive
(define-private (retrieve-archive-dimensions (archive-id uint))
  (default-to u0
    (get archive-dimensions
      (map-get? digital-archives { archive-id: archive-id })
    )
  )
)

;; Validates a single classification tag for proper formatting
(define-private (valid-classification? (classification (string-ascii 32)))
  (and
    (> (len classification) u0)
    (< (len classification) u33)
  )
)

;; Validates an entire list of classification tags
(define-private (validate-classifications (classifications (list 10 (string-ascii 32))))
  (and
    (> (len classifications) u0)
    (<= (len classifications) u10)
    (is-eq (len (filter valid-classification? classifications)) (len classifications))
  )
)

;; Confirms caller is the registered steward of an archive
(define-private (is-archive-steward? (archive-id uint) (user principal))
  (match (map-get? digital-archives { archive-id: archive-id })
    archive-data (is-eq (get archive-steward archive-data) user)
    false
  )
)

;; ====================================================================================
;; Public Archive Management Functions
;; ====================================================================================

;; Register a new digital archive with metadata and classifications
(define-public (register-archive 
  (name (string-ascii 64)) 
  (dimensions uint) 
  (summary (string-ascii 128)) 
  (classifications (list 10 (string-ascii 32)))
)
  (let
    (
      (new-archive-id (+ (var-get archive-registry-size) u1))
    )
    ;; Input validation
    (asserts! (> (len name) u0) err-invalid-archive-name)
    (asserts! (< (len name) u65) err-invalid-archive-name)
    (asserts! (> dimensions u0) err-invalid-archive-dimensions)
    (asserts! (< dimensions u1000000000) err-invalid-archive-dimensions)
    (asserts! (> (len summary) u0) err-invalid-archive-name)
    (asserts! (< (len summary) u129) err-invalid-archive-name)
    (asserts! (validate-classifications classifications) err-invalid-classification)

    ;; Create new archive record
    (map-insert digital-archives
      { archive-id: new-archive-id }
      {
        archive-name: name,
        archive-steward: tx-sender,
        archive-dimensions: dimensions,
        registration-timestamp: block-height,
        archive-summary: summary,
        archive-classifications: classifications
      }
    )

    ;; Grant access to steward automatically
    (map-insert archive-access-registry
      { archive-id: new-archive-id, accessor: tx-sender }
      { access-granted: true }
    )

    ;; Update registry size
    (var-set archive-registry-size new-archive-id)
    (ok new-archive-id)
  )
)

;; Update existing archive metadata and content
(define-public (modify-archive 
  (archive-id uint) 
  (updated-name (string-ascii 64)) 
  (updated-dimensions uint) 
  (updated-summary (string-ascii 128)) 
  (updated-classifications (list 10 (string-ascii 32)))
)
  (let
    (
      (archive-data (unwrap! (map-get? digital-archives { archive-id: archive-id }) err-archive-not-found))
    )
    ;; Verify archive exists and caller is steward
    (asserts! (archive-exists? archive-id) err-archive-not-found)
    (asserts! (is-eq (get archive-steward archive-data) tx-sender) err-operation-forbidden)

    ;; Validate inputs
    (asserts! (> (len updated-name) u0) err-invalid-archive-name)
    (asserts! (< (len updated-name) u65) err-invalid-archive-name)
    (asserts! (> updated-dimensions u0) err-invalid-archive-dimensions)
    (asserts! (< updated-dimensions u1000000000) err-invalid-archive-dimensions)
    (asserts! (> (len updated-summary) u0) err-invalid-archive-name)
    (asserts! (< (len updated-summary) u129) err-invalid-archive-name)
    (asserts! (validate-classifications updated-classifications) err-invalid-classification)

    ;; Update archive record
    (map-set digital-archives
      { archive-id: archive-id }
      (merge archive-data { 
        archive-name: updated-name, 
        archive-dimensions: updated-dimensions, 
        archive-summary: updated-summary, 
        archive-classifications: updated-classifications 
      })
    )
    (ok true)
  )
)

;; Transfer stewardship of an archive to another user
(define-public (transfer-archive-stewardship (archive-id uint) (new-steward principal))
  (let
    (
      (archive-data (unwrap! (map-get? digital-archives { archive-id: archive-id }) err-archive-not-found))
    )
    ;; Verify archive exists and caller is current steward
    (asserts! (archive-exists? archive-id) err-archive-not-found)
    (asserts! (is-eq (get archive-steward archive-data) tx-sender) err-operation-forbidden)

    ;; Transfer stewardship
    (map-set digital-archives
      { archive-id: archive-id }
      (merge archive-data { archive-steward: new-steward })
    )
    (ok true)
  )
)

;; Permanently remove an archive from the system
(define-public (purge-archive (archive-id uint))
  (let
    (
      (archive-data (unwrap! (map-get? digital-archives { archive-id: archive-id }) err-archive-not-found))
    )
    ;; Verify archive exists and caller is steward
    (asserts! (archive-exists? archive-id) err-archive-not-found)
    (asserts! (is-eq (get archive-steward archive-data) tx-sender) err-operation-forbidden)

    ;; Remove archive record
    (map-delete digital-archives { archive-id: archive-id })
    (ok true)
  )
)

;; ====================================================================================
;; Access Control Functions
;; ====================================================================================

;; Remove accessor permissions for a specified archive
(define-public (remove-archive-access (archive-id uint) (accessor principal))
  (let
    (
      (archive-data (unwrap! (map-get? digital-archives { archive-id: archive-id }) err-archive-not-found))
    )
    ;; Verify archive exists and caller is steward
    (asserts! (archive-exists? archive-id) err-archive-not-found)
    (asserts! (is-eq (get archive-steward archive-data) tx-sender) err-operation-forbidden)
    (asserts! (not (is-eq accessor tx-sender)) err-invalid-archive-name) ;; Steward cannot remove own access

    ;; Remove access permission
    (map-delete archive-access-registry { archive-id: archive-id, accessor: accessor })
    (ok true)
  )
)


;; Retrieve archive data with access controls
(define-public (access-archive (archive-id uint))
  (let
    (
      (archive-data (unwrap! (map-get? digital-archives { archive-id: archive-id }) err-archive-not-found))
      (access-record (map-get? archive-access-registry { archive-id: archive-id, accessor: tx-sender }))
    )
    ;; Verify archive exists
    (asserts! (archive-exists? archive-id) err-archive-not-found)

    ;; Check if caller has access rights
    (asserts! (or 
                (is-eq (get archive-steward archive-data) tx-sender)  ;; Is the steward
                (is-some access-record)                              ;; Has an access record
                (and (is-some access-record) 
                     (get access-granted (unwrap! access-record err-viewing-restriction)))  ;; Access is granted
              ) 
              err-viewing-restriction)

    ;; Return archive data
    (ok archive-data)
  )
)

;; ====================================================================================
;; Authentication and Verification Functions
;; ====================================================================================

;; Authenticate an archive (for authorized examiners only)
(define-public (authenticate-archive (archive-id uint) (authentication-notes (string-ascii 256)))
  (let
    (
      (archive-data (unwrap! (map-get? digital-archives { archive-id: archive-id }) err-archive-not-found))
      (examiner-status (unwrap! (map-get? authorized-examiners { examiner: tx-sender }) err-operation-forbidden))
    )
    ;; Verify archive exists and caller is authorized examiner
    (asserts! (archive-exists? archive-id) err-archive-not-found)
    (asserts! (get authorization-status examiner-status) err-operation-forbidden)

    (ok true)
  )
)


;; Retrieve authentication record for an archive
(define-public (check-archive-authentication (archive-id uint))
  (let
    (
      (archive-data (unwrap! (map-get? digital-archives { archive-id: archive-id }) err-archive-not-found))
      (authentication-record (map-get? archive-authentication-registry { archive-id: archive-id }))
    )
    ;; Verify archive exists
    (asserts! (archive-exists? archive-id) err-archive-not-found)

    ;; Return authentication data if available
    (ok (default-to 
      {
        authentication-status: false,
        authenticated-by: system-curator,
        authentication-timestamp: u0,
        examiner-notes: ""
      }
      authentication-record))
  )
)



