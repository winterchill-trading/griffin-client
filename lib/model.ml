(* Keep in sync with model.mli: one record per resource, JSON keys in [@key]. *)
open! Core
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Json = struct
  type t = Yojson.Safe.t

  let t_of_yojson j = j
  let yojson_of_t j = j
  let sexp_of_t j = Sexp.Atom (Yojson.Safe.to_string j)
end

module Money = struct
  type t =
    { currency : string [@key "currency"]
    ; value : string [@key "value"]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Organization = struct
  type t =
    { organization_url : string [@key "organization-url"]
    ; display_name : string [@key "display-name"]
    ; organization_mode : string [@key "organization-mode"]
    ; own_legal_person_url : string option
         [@key "own-legal-person-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; organization_legal_persons_url : string option
         [@key "organization-legal-persons-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; organization_bank_accounts_url : string option
         [@key "organization-bank-accounts-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; organization_bank_account_products_url : string option
         [@key "organization-bank-account-products-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; organization_payments_url : string option
         [@key "organization-payments-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; organization_events_url : string option
         [@key "organization-events-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; organization_webhooks_url : string option
         [@key "organization-webhooks-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; organization_workflows_url : string option
         [@key "organization-workflows-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; can_decide_on_verifications : bool option
         [@key "can-decide-on-verifications?"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Decision = struct
  type t =
    { legal_person_url : string [@key "legal-person-url"]
    ; decision_outcome : string [@key "decision-outcome"]
    ; verification_url : string option
         [@key "verification-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; decision_notes : string option
         [@key "decision-notes"] [@default None] [@yojson_drop_if Option.is_none]
    ; decision_maker : string option
         [@key "decision-maker"] [@default None] [@yojson_drop_if Option.is_none]
    ; created_at : string [@key "created-at"]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Legal_person = struct
  type t =
    { legal_person_url : string [@key "legal-person-url"]
    ; legal_person_type : string [@key "legal-person-type"]
    ; display_name : string [@key "display-name"]
    ; created_at : string [@key "created-at"]
    ; application_status : string option
         [@key "application-status"] [@default None] [@yojson_drop_if Option.is_none]
    ; legal_person_status : string option
         [@key "legal-person-status"] [@default None] [@yojson_drop_if Option.is_none]
    ; latest_decision : Decision.t option
         [@key "latest-decision"] [@default None] [@yojson_drop_if Option.is_none]
    ; legal_person_verifications_url : string option
         [@key "legal-person-verifications-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; legal_person_decisions_url : string option
         [@key "legal-person-decisions-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; legal_person_bank_payees_url : string option
         [@key "legal-person-bank-payees-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; legal_person_claims_url : string option
         [@key "legal-person-claims-url"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Workflow = struct
  type t =
    { workflow_url : string [@key "workflow-url"]
    ; display_name : string [@key "display-name"]
    ; legal_person_type : string [@key "legal-person-type"]
    ; description : string option
         [@key "description"] [@default None] [@yojson_drop_if Option.is_none]
    ; disabled : bool option
         [@key "disabled?"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Verification = struct
  type t =
    { verification_url : string [@key "verification-url"]
    ; verification_status : string [@key "verification-status"]
    ; legal_person_url : string [@key "legal-person-url"]
    ; workflow_url : string [@key "workflow-url"]
    ; created_at : string [@key "created-at"]
    ; risk_rating : string option
         [@key "risk-rating"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Bank_product = struct
  type t =
    { bank_account_product_url : string [@key "bank-account-product-url"]
    ; bank_account_product_accounts_url : string
         [@key "bank-account-product-accounts-url"]
    ; display_name : string [@key "display-name"]
    ; bank_account_product_class : string [@key "bank-account-product-class"]
    ; bank_account_product_status : string option
         [@key "bank-account-product-status"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; funding_type : string option
         [@key "funding-type"] [@default None] [@yojson_drop_if Option.is_none]
    ; owner_type : string option
         [@key "owner-type"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Bank_address = struct
  type t =
    { account_holder : string [@key "account-holder"]
    ; bank_id : string [@key "bank-id"]
    ; bank_id_code : string option
         [@key "bank-id-code"] [@default None] [@yojson_drop_if Option.is_none]
    ; account_number : string [@key "account-number"]
    ; account_number_code : string option
         [@key "account-number-code"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Bank_account = struct
  type t =
    { account_url : string [@key "account-url"]
    ; display_name : string [@key "display-name"]
    ; account_status : string [@key "account-status"]
    ; bank_product_type : string [@key "bank-product-type"]
    ; account_balance : Money.t [@key "account-balance"]
    ; available_balance : Money.t option
         [@key "available-balance"] [@default None] [@yojson_drop_if Option.is_none]
    ; bank_addresses : Bank_address.t list [@key "bank-addresses"] [@default []]
    ; owner_url : string option
         [@key "owner-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; beneficiary_url : string option
         [@key "beneficiary-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; controller_url : string option
         [@key "controller-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; bank_account_product_url : string option
         [@key "bank-account-product-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; account_transactions_url : string option
         [@key "account-transactions-url"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; account_payments_url : string option
         [@key "account-payments-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; account_admissions_url : string option
         [@key "account-admissions-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; account_submissions_url : string option
         [@key "account-submissions-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; created_at : string option
         [@key "created-at"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Transaction = struct
  type t =
    { account_transaction_url : string [@key "account-transaction-url"]
    ; account_url : string [@key "account-url"]
    ; balance_change : Money.t [@key "balance-change"]
    ; balance_change_direction : string [@key "balance-change-direction"]
    ; account_balance : Money.t [@key "account-balance"]
    ; transaction_origin_type : string [@key "transaction-origin-type"]
    ; post_datetime : string option
         [@key "post-datetime"] [@default None] [@yojson_drop_if Option.is_none]
    ; effective_at : string option
         [@key "effective-at"] [@default None] [@yojson_drop_if Option.is_none]
    ; payment_url : string option
         [@key "payment-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; reference : string option
         [@key "reference"] [@default None] [@yojson_drop_if Option.is_none]
    ; description : string option
         [@key "description"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Party = struct
  type t =
    { creditor_type : string option
         [@key "creditor-type"] [@default None] [@yojson_drop_if Option.is_none]
    ; account_holder : string option
         [@key "account-holder"] [@default None] [@yojson_drop_if Option.is_none]
    ; account_number : string option
         [@key "account-number"] [@default None] [@yojson_drop_if Option.is_none]
    ; account_number_code : string option
         [@key "account-number-code"] [@default None] [@yojson_drop_if Option.is_none]
    ; bank_id : string option
         [@key "bank-id"] [@default None] [@yojson_drop_if Option.is_none]
    ; bank_id_code : string option
         [@key "bank-id-code"] [@default None] [@yojson_drop_if Option.is_none]
    ; account_url : string option
         [@key "account-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; payee_url : string option
         [@key "payee-url"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Payment = struct
  type t =
    { payment_url : string [@key "payment-url"]
    ; payment_direction : string [@key "payment-direction"]
    ; payment_type : string option
         [@key "payment-type"] [@default None] [@yojson_drop_if Option.is_none]
    ; payment_amount : Money.t [@key "payment-amount"]
    ; payment_reference : string option
         [@key "payment-reference"] [@default None] [@yojson_drop_if Option.is_none]
    ; creditor : Party.t [@key "creditor"]
    ; debtor : Party.t option
         [@key "debtor"] [@default None] [@yojson_drop_if Option.is_none]
    ; payment_submissions_url : string option
         [@key "payment-submissions-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; payment_admissions_url : string option
         [@key "payment-admissions-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; created_at : string [@key "created-at"]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Scheme_information = struct
  type t =
    { payment_scheme : string [@key "payment-scheme"]
    ; end_to_end_identification : string option
         [@key "end-to-end-identification"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; scheme_status_code : string option
         [@key "scheme-status-code"] [@default None] [@yojson_drop_if Option.is_none]
    ; scheme_status_code_description : string option
         [@key "scheme-status-code-description"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Submission = struct
  type t =
    { submission_url : string [@key "submission-url"]
    ; submission_status : string [@key "submission-status"]
    ; payment_url : string [@key "payment-url"]
    ; created_at : string [@key "created-at"]
    ; account_url : string option
         [@key "account-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; submission_scheme_information : Scheme_information.t option
         [@key "submission-scheme-information"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; scheduled_at : string option
         [@key "scheduled-at"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Admission = struct
  type t =
    { admission_url : string [@key "admission-url"]
    ; admission_status : string [@key "admission-status"]
    ; payment_url : string [@key "payment-url"]
    ; created_at : string [@key "created-at"]
    ; account_url : string option
         [@key "account-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; admission_scheme_information : Scheme_information.t option
         [@key "admission-scheme-information"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Payee = struct
  type t =
    { payee_url : string [@key "payee-url"]
    ; account_holder : string [@key "account-holder"]
    ; account_number : string [@key "account-number"]
    ; bank_id : string [@key "bank-id"]
    ; payee_status : string option
         [@key "payee-status"] [@default None] [@yojson_drop_if Option.is_none]
    ; legal_person_url : string option
         [@key "legal-person-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; cop_request_url : string option
         [@key "cop-request-url"] [@default None] [@yojson_drop_if Option.is_none]
    ; created_at : string option
         [@key "created-at"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Cop_account = struct
  type t =
    { account_number : string [@key "account-number"]
    ; bank_id : string [@key "bank-id"]
    ; account_classification : string [@key "account-classification"]
    ; name : string [@key "name"]
    ; secondary_reference_data : string option
         [@key "secondary-reference-data"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    ; requester_legal_person_url : string [@key "requester-legal-person-url"]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Cop_response = struct
  type t =
    { status : string [@key "status"]
    ; result : string [@key "result"]
    ; reason : string option
         [@key "reason"] [@default None] [@yojson_drop_if Option.is_none]
    ; suggested_name : string option
         [@key "suggested-name"] [@default None] [@yojson_drop_if Option.is_none]
    ; suggested_account_classification : string option
         [@key "suggested-account-classification"]
         [@default None]
         [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Cop_request = struct
  type t =
    { cop_request_url : string [@key "cop-request-url"]
    ; account : Cop_account.t [@key "account"]
    ; cop_response : Cop_response.t [@key "cop-response"]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Event = struct
  type t =
    { event_url : string [@key "event-url"]
    ; event_type : string [@key "event-type"]
    ; event_payload : Json.t [@key "event-payload"]
    ; created_at : string [@key "created-at"]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end

module Webhook = struct
  type t =
    { webhook_url : string [@key "webhook-url"]
    ; webhook_destination_url : string [@key "webhook-destination-url"]
    ; webhook_state : string [@key "webhook-state"]
    ; webhook_description : string option
         [@key "webhook-description"] [@default None] [@yojson_drop_if Option.is_none]
    ; created_at : string option
         [@key "created-at"] [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving yojson, sexp_of, fields ~getters] [@@yojson.allow_extra_fields]
end
