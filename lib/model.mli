(** Typed Griffin resources. Field names follow the JSON keys ([account-url] is
    [account_url]). Enumerations are kept as strings because Griffin adds values within a
    version; unknown fields are ignored and optional ones are dropped when absent, so
    [t_of_yojson (yojson_of_t x) = x]. *)

open! Core

module Json : sig
  type t = Yojson.Safe.t [@@deriving yojson, sexp_of]
end

(** An amount; [value] is a decimal string such as ["12.34"]. *)
module Money : sig
  type t =
    { currency : string
    ; value : string
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** The caller's organization ([organization-url] from the index). *)
module Organization : sig
  type t =
    { organization_url : string
    ; display_name : string
    ; organization_mode : string
    ; own_legal_person_url : string option
    ; organization_legal_persons_url : string option
    ; organization_bank_accounts_url : string option
    ; organization_bank_account_products_url : string option
    ; organization_payments_url : string option
    ; organization_events_url : string option
    ; organization_webhooks_url : string option
    ; organization_workflows_url : string option
    ; can_decide_on_verifications : bool option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** An onboarding decision on a legal person. *)
module Decision : sig
  type t =
    { legal_person_url : string
    ; decision_outcome : string
    ; verification_url : string option
    ; decision_notes : string option
    ; decision_maker : string option
    ; created_at : string
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** A customer or the organization itself (individual or corporation). *)
module Legal_person : sig
  type t =
    { legal_person_url : string
    ; legal_person_type : string
    ; display_name : string
    ; created_at : string
    ; application_status : string option
    ; legal_person_status : string option
    ; latest_decision : Decision.t option
    ; legal_person_verifications_url : string option
    ; legal_person_decisions_url : string option
    ; legal_person_bank_payees_url : string option
    ; legal_person_claims_url : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** An onboarding workflow (which claims a verification needs). *)
module Workflow : sig
  type t =
    { workflow_url : string
    ; display_name : string
    ; legal_person_type : string
    ; description : string option
    ; disabled : bool option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** A run of a workflow's checks on a legal person. *)
module Verification : sig
  type t =
    { verification_url : string
    ; verification_status : string
    ; legal_person_url : string
    ; workflow_url : string
    ; created_at : string
    ; risk_rating : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** A bank account product the organization may open accounts with. *)
module Bank_product : sig
  type t =
    { bank_account_product_url : string
    ; bank_account_product_accounts_url : string
    ; display_name : string
    ; bank_account_product_class : string
    ; bank_account_product_status : string option
    ; funding_type : string option
    ; owner_type : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** Sort code and account number of an account. *)
module Bank_address : sig
  type t =
    { account_holder : string
    ; bank_id : string
    ; bank_id_code : string option
    ; account_number : string
    ; account_number_code : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** A bank account. [account_status] goes [opening] -> [open] -> ... -> [closed]. *)
module Bank_account : sig
  type t =
    { account_url : string
    ; display_name : string
    ; account_status : string
    ; bank_product_type : string
    ; account_balance : Money.t
    ; available_balance : Money.t option
    ; bank_addresses : Bank_address.t list
    ; owner_url : string option
    ; beneficiary_url : string option
    ; controller_url : string option
    ; bank_account_product_url : string option
    ; account_transactions_url : string option
    ; account_payments_url : string option
    ; account_admissions_url : string option
    ; account_submissions_url : string option
    ; created_at : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** A posted balance change on an account. *)
module Transaction : sig
  type t =
    { account_transaction_url : string
    ; account_url : string
    ; balance_change : Money.t
    ; balance_change_direction : string
    ; account_balance : Money.t
    ; transaction_origin_type : string
    ; post_datetime : string option
    ; effective_at : string option
    ; payment_url : string option
    ; reference : string option
    ; description : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** Creditor or debtor of a payment. *)
module Party : sig
  type t =
    { creditor_type : string option
    ; account_holder : string option
    ; account_number : string option
    ; account_number_code : string option
    ; bank_id : string option
    ; bank_id_code : string option
    ; account_url : string option
    ; payee_url : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** A payment. Creating one moves no money; submitting it does. *)
module Payment : sig
  type t =
    { payment_url : string
    ; payment_direction : string
    ; payment_type : string option
    ; payment_amount : Money.t
    ; payment_reference : string option
    ; creditor : Party.t
    ; debtor : Party.t option
    ; payment_submissions_url : string option
    ; payment_admissions_url : string option
    ; created_at : string
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** Scheme details of a submission or admission. *)
module Scheme_information : sig
  type t =
    { payment_scheme : string
    ; end_to_end_identification : string option
    ; scheme_status_code : string option
    ; scheme_status_code_description : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** An outbound payment sent to a scheme. *)
module Submission : sig
  type t =
    { submission_url : string
    ; submission_status : string
    ; payment_url : string
    ; created_at : string
    ; account_url : string option
    ; submission_scheme_information : Scheme_information.t option
    ; scheduled_at : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** An inbound payment received from a scheme. *)
module Admission : sig
  type t =
    { admission_url : string
    ; admission_status : string
    ; payment_url : string
    ; created_at : string
    ; account_url : string option
    ; admission_scheme_information : Scheme_information.t option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** A saved UK account a legal person pays. *)
module Payee : sig
  type t =
    { payee_url : string
    ; account_holder : string
    ; account_number : string
    ; bank_id : string
    ; payee_status : string option
    ; legal_person_url : string option
    ; cop_request_url : string option
    ; created_at : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** The account a Confirmation of Payee request checks. *)
module Cop_account : sig
  type t =
    { account_number : string
    ; bank_id : string
    ; account_classification : string
    ; name : string
    ; secondary_reference_data : string option
    ; requester_legal_person_url : string
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** [status] is [verified] only for a full match. *)
module Cop_response : sig
  type t =
    { status : string
    ; result : string
    ; reason : string option
    ; suggested_name : string option
    ; suggested_account_classification : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** A Confirmation of Payee check and its answer. *)
module Cop_request : sig
  type t =
    { cop_request_url : string
    ; account : Cop_account.t
    ; cop_response : Cop_response.t
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** A resource change. [event_type] is the resource and change, e.g. [payment-created]. *)
module Event : sig
  type t =
    { event_url : string
    ; event_type : string
    ; event_payload : Json.t
    ; created_at : string
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end

(** The organization's single webhook (read-only in this client). *)
module Webhook : sig
  type t =
    { webhook_url : string
    ; webhook_destination_url : string
    ; webhook_state : string
    ; webhook_description : string option
    ; created_at : string option
    }
  [@@deriving yojson, sexp_of, fields ~getters]
end
