#lang racket/base

;; Definitions with contracts and contract documentation.

(require racket/contract "../latent-contract.rkt" racket/provide racket/match
         (for-syntax racket/base racket/list racket/syntax syntax/parse racket/provide-transform)
         (prefix-in s. scribble/manual)
         (prefix-in s. scribble/core)
         (prefix-in s. scribble/html-properties))

(provide defthing defproc defparam defcontract
         only-doc-out doc-apply)

(begin-for-syntax
  (define-syntax-class argument-spec
    #:description "argument specification"
    (pattern [name:id contract:expr])
    (pattern [name:id contract:expr default:expr])
    (pattern [kw:keyword name:id contract:expr])
    (pattern [kw:keyword name:id contract:expr default:expr])))

;; ===================================================================================================
;; Helpers

(define-for-syntax (get-required-contract arg-stx)
  (syntax-parse arg-stx
    [(name:id contract:expr)             (list #'contract)]
    [(kw:keyword name:id contract:expr)  (list #'kw #'contract)]
    [_  empty]))

(define-for-syntax (get-optional-contract arg-stx)
  (syntax-parse arg-stx
    [(name:id contract:expr default:expr)             (list #'contract)]
    [(kw:keyword name:id contract:expr default:expr)  (list #'kw #'contract)]
    [_  empty]))

(define-for-syntax (remove-contract arg-stx)
  (syntax-parse arg-stx
    [(name:id contract:expr)                          (list #'name)]
    [(name:id contract:expr default:expr)             (list #'(name default))]
    [(kw:keyword name:id contract:expr)               (list #'kw #'name)]
    [(kw:keyword name:id contract:expr default:expr)  (list #'kw #'(name default))]))

(define-for-syntax (parameter-name->arg-name name-stx)
  (define name-str (symbol->string (syntax->datum name-stx)))
  (define arg-name-str
    (cond [(regexp-match #rx".*-(.*)$" name-str)  => (λ (m) (last m))]
          [(regexp-match #rx"^$" name-str)        => (λ (m) "value")]
          [else  (substring name-str 0 1)]))
  (datum->syntax name-stx (string->symbol arg-name-str)))

;; ===================================================================================================
;; Forms to define things with a contract and documentation

;; Define a thing, optionally documenting the value of the thing
(define-syntax (defthing stx)
  (syntax-parse stx
    [(_ name:id contract:expr #:document-value value:expr)
     (with-syntax ([name:doc             (format-id #'name "~a:doc" #'name)])
       (syntax/loc stx
         (begin
           (define/latent-contract name contract value)
           (define-syntax (name:doc doc-stx)
             (syntax-case doc-stx ()
               [(ctx . pre-flows)
                (with-syntax ([doc-name      (datum->syntax #'ctx (syntax-e #'name))]
                              [doc-contract  (quote-syntax contract)]
                              [doc-value     (quote-syntax value)])
                  (syntax/loc doc-stx
                    (s.defthing doc-name doc-contract #:value doc-value
                                . pre-flows)))])))))]
    [(_ name:id contract:expr value:expr)
     (with-syntax ([name:doc             (format-id #'name "~a:doc" #'name)])
       (syntax/loc stx
         (begin
           (define/latent-contract name contract value)
           (define-syntax (name:doc doc-stx)
             (syntax-case doc-stx ()
               [(ctx . pre-flows)
                (with-syntax ([doc-name      (datum->syntax #'ctx (syntax-e #'name))]
                              [doc-contract  (quote-syntax contract)])
                  (syntax/loc doc-stx
                    (s.defthing doc-name doc-contract . pre-flows)))])))))]))

(define-for-syntax (wrap-procedure-body stx)
  (syntax-case stx ()
    [(e)  #'e]
    [(e ...)  #'(let () e ...)]))

;; Define a procedure
(define-syntax (defproc stx)
  (syntax-parse stx
    [(_ (name:id arg:argument-spec ...) result:expr #:document-body body ...+)
     (define arg-list (syntax->list #'(arg ...)))
     (with-syntax ([name:doc            (format-id #'name "~a:doc" #'name)]
                   [(new-arg ...)       (append* (map remove-contract arg-list))]
                   [(req-contract ...)  (append* (map get-required-contract arg-list))]
                   [(opt-contract ...)  (append* (map get-optional-contract arg-list))]
                   [wrapped-body        (wrap-procedure-body #'(body ...))])
       (syntax/loc stx
         (begin
           (define/latent-contract (name new-arg ...) (->* (req-contract ...) (opt-contract ...)
                                                           result)
             body ...)
           (define-syntax (name:doc doc-stx)
             (syntax-case doc-stx ()
               [(ctx . pre-flows)
                (with-syntax ([doc-name    (datum->syntax #'ctx (syntax-e #'name))]
                              [doc-args    (quote-syntax (arg ...))]
                              [doc-result  (quote-syntax result)]
                              [doc-body    (quote-syntax #'wrapped-body)])
                  (syntax/loc doc-stx
                    (s.defproc (doc-name . doc-args) doc-result #:value doc-body
                               . pre-flows)))])))))]
    [(_ (name:id arg:argument-spec ...) result:expr body ...+)
     (define arg-list (syntax->list #'(arg ...)))
     (with-syntax ([name:doc            (format-id #'name "~a:doc" #'name)]
                   [(new-arg ...)       (append* (map remove-contract arg-list))]
                   [(req-contract ...)  (append* (map get-required-contract arg-list))]
                   [(opt-contract ...)  (append* (map get-optional-contract arg-list))])
       (syntax/loc stx
         (begin
           (define/latent-contract (name new-arg ...) (->* (req-contract ...) (opt-contract ...)
                                                           result)
             body ...)
           (define-syntax (name:doc doc-stx)
             (syntax-case doc-stx ()
               [(ctx . pre-flows)
                (with-syntax ([doc-name    (datum->syntax #'ctx (syntax-e #'name))]
                              [doc-args    (quote-syntax (arg ...))]
                              [doc-result  (quote-syntax result)])
                  (syntax/loc doc-stx
                    (s.defproc (doc-name . doc-args) doc-result . pre-flows)))])))))]))

;; Define a parameter
(define-syntax (defparam stx)
  (syntax-parse stx
    [(_ name:id arg:id contract:expr default:expr)
     (with-syntax ([name:doc             (format-id #'name "~a:doc" #'name)])
       (syntax/loc stx
         (begin
           (define/latent-contract name (parameter/c contract) (make-parameter default))
           (define-syntax (name:doc doc-stx)
             (syntax-case doc-stx ()
               [(ctx . pre-flows)
                (with-syntax ([doc-name      (datum->syntax #'ctx (syntax-e #'name))]
                              [doc-arg       (datum->syntax #'ctx (syntax-e #'arg))]
                              [doc-contract  (quote-syntax contract)]
                              [doc-default   (quote-syntax default)])
                  #'(s.defparam doc-name doc-arg doc-contract #:value doc-default
                                . pre-flows))])))))]
    [(_ name:id contract:expr default:expr)
     (quasisyntax/loc stx
       (defparam name #,(parameter-name->arg-name #'name) contract default))]))

;; Define a contract or a procedure that returns a contract
(define-syntax (defcontract stx)
  (syntax-parse stx
    [(_ name:id value:expr)
     (syntax/loc stx (defthing name contract? #:document-value value))]
    [(_ (name:id arg:argument-spec ...) body)
     (syntax/loc stx (defproc (name arg ...) contract? #:document-body body))]))

;; ===================================================================================================
;; Getting documentation

(define-syntax only-doc-out
  (make-provide-pre-transformer
   (λ (stx modes)
     (syntax-case stx ()
       [(_ provide-spec)
        (pre-expand-export
         (syntax/loc stx
           (matching-identifiers-out #rx".*:doc$" provide-spec))
         modes)]))))

;; Applies the documentation transformer (use within a scribble/manual module)
(define-syntax (doc-apply stx)
  (syntax-parse stx
    [(_ name:id . pre-flows)
     (with-syntax ([name:doc  (format-id #'name "~a:doc" #'name)])
       (syntax-protect
        (syntax/loc stx (name:doc . pre-flows))))]))
