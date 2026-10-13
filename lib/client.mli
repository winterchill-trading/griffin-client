(** Typed operations over the Griffin API. Paths come from the hypermedia links of the
    index, the organization and each resource; only the Confirmation of Payee and
    simulation endpoints, which no resource links to, are built from the organization URL. *)

open! Core
open! Async
open Model

type t

(** Fetch the index and the organization. Refuses a [live-mode] organization unless the
    config was created with [~live:true]. *)
val connect : Transport.t -> t Or_error.t Deferred.t

val transport : t -> Transport.t
val organization : t -> Organization.t

(** Every link relation discovered from the index and the organization. *)
val links : t -> Links.t

(** {2 Generic navigation} *)

val get : t -> string -> (Yojson.Safe.t -> 'a) -> 'a Or_error.t Deferred.t

(** Append [page[size]=n] (1 to 200) to a list link. *)
val with_page_size : string -> int -> string

(** Fetch one page of a list; [key] is the array field (["accounts"], ...). *)
val page
  :  t
  -> string
  -> key:string
  -> (Yojson.Safe.t -> 'a)
  -> 'a Page.t Or_error.t Deferred.t

(** Fold over every item of every page, following [links.next]. *)
val fold
  :  t
  -> string
  -> key:string
  -> (Yojson.Safe.t -> 'a)
  -> init:'acc
  -> f:('acc -> 'a -> 'acc)
  -> 'acc Or_error.t Deferred.t

(** The items of every page as a pipe; a failed page ends the pipe with the error as the
    last element. *)
val pipe
  :  t
  -> string
  -> key:string
  -> (Yojson.Safe.t -> 'a)
  -> 'a Or_error.t Pipe.Reader.t

(** {2 Onboarding} *)

val workflows : t -> Workflow.t list Or_error.t Deferred.t
val legal_persons : ?page_size:int -> t -> Legal_person.t Page.t Or_error.t Deferred.t
val legal_person : t -> string -> Legal_person.t Or_error.t Deferred.t

(** [POST organization-legal-persons-url] with a request body such as
    {!Claims.individual}. *)
val create_legal_person : t -> Yojson.Safe.t -> Legal_person.t Or_error.t Deferred.t

val start_verification
  :  t
  -> Legal_person.t
  -> workflow_url:string
  -> Verification.t Or_error.t Deferred.t

val verification : t -> string -> Verification.t Or_error.t Deferred.t
val decisions : t -> Legal_person.t -> Decision.t list Or_error.t Deferred.t

(** Record a decision. In the sandbox the organization decides; in live mode Griffin does,
    and this call is refused. *)
val decide
  :  t
  -> Legal_person.t
  -> verification_url:string
  -> outcome:[ `Accepted | `Declined ]
  -> notes:string
  -> Decision.t Or_error.t Deferred.t

(** {2 Accounts} *)

val bank_products : t -> Bank_product.t list Or_error.t Deferred.t
val bank_accounts : ?page_size:int -> t -> Bank_account.t Page.t Or_error.t Deferred.t
val bank_account : t -> string -> Bank_account.t Or_error.t Deferred.t

val open_account
  :  ?owner_url:string
  -> ?beneficiary_url:string
  -> t
  -> Bank_product.t
  -> display_name:string
  -> Bank_account.t Or_error.t Deferred.t

(** Poll until [account-status] is [open] (default: every second, 60 tries). *)
val wait_until_open
  :  ?interval:Time_ns.Span.t
  -> ?tries:int
  -> t
  -> Bank_account.t
  -> Bank_account.t Or_error.t Deferred.t

val transactions
  :  ?page_size:int
  -> t
  -> Bank_account.t
  -> Transaction.t Page.t Or_error.t Deferred.t

(** {2 Payments} *)

module Creditor : sig
  type t =
    | Uk_domestic of
        { account_holder : string
        ; account_number : string (** 8 digits *)
        ; sort_code : string (** 6 digits, no dashes *)
        }
    | Payee of string (** payee URL *)
    | Griffin_account of string (** account URL in the same organization *)
  [@@deriving sexp_of]

  val to_json : t -> Yojson.Safe.t
end

(** Create (not send) a payment of GBP [amount] (a decimal string such as ["12.34"]). Not
    idempotent: never retried. *)
val create_payment
  :  ?reference:string
  -> t
  -> Bank_account.t
  -> creditor:Creditor.t
  -> amount:string
  -> Payment.t Or_error.t Deferred.t

(** Submit a payment to a scheme ([fps] or [book-transfer]). Retried on 429/5xx: a
    repeated submission answers 410, reported as [`Already_submitted] with the payment's
    submissions. *)
val submit_payment
  :  t
  -> Payment.t
  -> scheme:[ `Fps | `Book_transfer ]
  -> [ `Submitted of Submission.t | `Already_submitted of Submission.t list ] Or_error.t
       Deferred.t

val submission : t -> string -> Submission.t Or_error.t Deferred.t

val payments
  :  ?page_size:int
  -> t
  -> Bank_account.t
  -> Payment.t Page.t Or_error.t Deferred.t

val admissions : t -> Bank_account.t -> Admission.t list Or_error.t Deferred.t

(** {2 Payees and Confirmation of Payee} *)

val payees : t -> Legal_person.t -> Payee.t list Or_error.t Deferred.t

val create_payee
  :  ?cop_request_url:string
  -> t
  -> Legal_person.t
  -> account_holder:string
  -> account_number:string
  -> sort_code:string
  -> Payee.t Or_error.t Deferred.t

module Cop_check : sig
  type t =
    { name : string
    ; account_number : string
    ; sort_code : string
    ; classification : [ `Personal | `Business ]
    ; secondary_reference : string option
    ; requester_legal_person_url : string
    }
  [@@deriving sexp_of]

  val to_json : t -> Yojson.Safe.t
end

(** [POST <organization-url>/cop-request]. Errors such as [account-not-found] arrive as an
    [Api_error] (status 400). *)
val confirm_payee : t -> Cop_check.t -> Cop_request.t Or_error.t Deferred.t

(** Sandbox only (alpha API): force an outcome, e.g. ["full-match"], ["close-match-name"],
    ["no-match-name"], ["account-not-found"]. *)
val simulate_confirm_payee
  :  t
  -> Cop_check.t
  -> outcome:string
  -> Cop_request.t Or_error.t Deferred.t

(** {2 Events and webhooks} *)

val events : ?page_size:int -> t -> Event.t Page.t Or_error.t Deferred.t
val webhooks : t -> Webhook.t list Or_error.t Deferred.t
