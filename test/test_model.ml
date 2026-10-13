open! Core
open Griffin_client
open Model

module type Codec = sig
  type t [@@deriving yojson, sexp_of]
end

let load name = Yojson.Safe.from_file ("fixtures/" ^ name ^ ".json")

(* Decode, print, and check that re-encoding then decoding gives the same value. *)
let one (type a) name (module M : Codec with type t = a) =
  let v = ok_exn (Page.decode M.t_of_yojson (load name)) in
  let again = ok_exn (Page.decode M.t_of_yojson (M.yojson_of_t v)) in
  [%test_result: Sexp.t] (M.sexp_of_t again) ~expect:(M.sexp_of_t v);
  print_s (M.sexp_of_t v)
;;

let page (type a) name ~key (module M : Codec with type t = a) =
  let p = ok_exn (Page.of_json ~key M.t_of_yojson (load name)) in
  List.iter p.items ~f:(fun v ->
    let again = ok_exn (Page.decode M.t_of_yojson (M.yojson_of_t v)) in
    [%test_result: Sexp.t] (M.sexp_of_t again) ~expect:(M.sexp_of_t v));
  p
;;

let%expect_test "organization" =
  one "organization" (module Organization);
  [%expect {|
    ((organization_url /v0/organizations/og.fixture01xxxxxxxxxxxxx)
     (display_name "Example Org") (organization_mode test-mode)
     (own_legal_person_url (/v0/legal-persons/lp.fixture01xxxxxxxxxxxxx))
     (organization_legal_persons_url
      (/v0/organizations/og.fixture01xxxxxxxxxxxxx/legal-persons))
     (organization_bank_accounts_url
      (/v0/organizations/og.fixture01xxxxxxxxxxxxx/bank/accounts))
     (organization_bank_account_products_url
      (/v0/organizations/og.fixture01xxxxxxxxxxxxx/bank/products))
     (organization_payments_url
      (/v0/organizations/og.fixture01xxxxxxxxxxxxx/payments))
     (organization_events_url
      (/v0/organizations/og.fixture01xxxxxxxxxxxxx/events))
     (organization_webhooks_url
      (/v0/organizations/og.fixture01xxxxxxxxxxxxx/webhooks))
     (organization_workflows_url
      (/v0/organizations/og.fixture01xxxxxxxxxxxxx/workflows))
     (can_decide_on_verifications (true)))
    |}]
;;

let%expect_test "legal person, verification, decisions, workflows" =
  one "legal-person" (module Legal_person);
  one "legal-person-created" (module Legal_person);
  one "verification" (module Verification);
  let d = page "decisions" ~key:"decisions" (module Decision) in
  print_s [%sexp (d : Decision.t Page.t)];
  let w = page "workflows" ~key:"workflows" (module Workflow) in
  print_s [%message (List.length w.items : int) (w.total : int option)];
  [%expect {|
    ((legal_person_url /v0/legal-persons/lp.fixture02xxxxxxxxxxxxx)
     (legal_person_type individual) (display_name "FIXTURE, Ada")
     (created_at 2026-10-13T19:50:29.343Z) (application_status (accepted))
     (legal_person_status (onboarded))
     (latest_decision
      (((legal_person_url /v0/legal-persons/lp.fixture02xxxxxxxxxxxxx)
        (decision_outcome accepted)
        (verification_url (/v0/verifications/vn.fixture01xxxxxxxxxxxxx))
        (decision_notes ("")) (decision_maker (system))
        (created_at 2026-10-13T19:50:34.162Z))))
     (legal_person_verifications_url
      (/v0/legal-persons/lp.fixture02xxxxxxxxxxxxx/verifications))
     (legal_person_decisions_url
      (/v0/legal-persons/lp.fixture02xxxxxxxxxxxxx/decisions))
     (legal_person_bank_payees_url
      (/v0/legal-persons/lp.fixture02xxxxxxxxxxxxx/bank/payees))
     (legal_person_claims_url
      (/v0/legal-persons/lp.fixture02xxxxxxxxxxxxx/claims)))
    ((legal_person_url /v0/legal-persons/lp.fixture02xxxxxxxxxxxxx)
     (legal_person_type individual) (display_name "FIXTURE, Ada")
     (created_at 2026-10-13T19:50:29.343Z) (application_status ())
     (legal_person_status ()) (latest_decision ())
     (legal_person_verifications_url
      (/v0/legal-persons/lp.fixture02xxxxxxxxxxxxx/verifications))
     (legal_person_decisions_url
      (/v0/legal-persons/lp.fixture02xxxxxxxxxxxxx/decisions))
     (legal_person_bank_payees_url
      (/v0/legal-persons/lp.fixture02xxxxxxxxxxxxx/bank/payees))
     (legal_person_claims_url
      (/v0/legal-persons/lp.fixture02xxxxxxxxxxxxx/claims)))
    ((verification_url /v0/verifications/vn.fixture01xxxxxxxxxxxxx)
     (verification_status checks-complete)
     (legal_person_url /v0/legal-persons/lp.fixture02xxxxxxxxxxxxx)
     (workflow_url /v0/workflows/wf.fixture01xxxxxxxxxxxxx)
     (created_at 2026-10-13T19:50:34.162Z) (risk_rating (low-risk)))
    ((items
      (((legal_person_url /v0/legal-persons/lp.fixture02xxxxxxxxxxxxx)
        (decision_outcome accepted)
        (verification_url (/v0/verifications/vn.fixture01xxxxxxxxxxxxx))
        (decision_notes ("")) (decision_maker (system))
        (created_at 2026-10-13T19:50:34.162Z))))
     (next ()) (prev ()) (total ()))
    (("List.length w.items" 6) (w.total (6)))
    |}]
;;

let%expect_test "products and accounts" =
  let p = page "bank-products" ~key:"bank-account-products" (module Bank_product) in
  List.iter p.items ~f:(fun p ->
    printf "%s %s\n" p.bank_account_product_class p.display_name);
  one "bank-account" (module Bank_account);
  let a = page "bank-accounts-page" ~key:"accounts" (module Bank_account) in
  print_s [%message (List.length a.items : int) (Option.is_some a.next : bool)];
  [%expect {|
    savings Easy access savings business
    savings Bare trust savings
    safeguarding Dedicated safeguarding
    embedded Embedded consumer
    embedded Embedded business
    savings Easy access savings consumer
    operational Operational
    safeguarding Pooled safeguarding
    client-money Pooled client money
    client-money Dedicated client money
    ((account_url /v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx)
     (display_name "griffin-client fixture A") (account_status open)
     (bank_product_type operational-account)
     (account_balance ((currency GBP) (value 999982.66)))
     (available_balance (((currency GBP) (value 999982.66))))
     (bank_addresses
      (((account_holder "griffin-client fixture A") (bank_id 000001)
        (bank_id_code (gbdsc)) (account_number 00000000)
        (account_number_code (bban)))))
     (owner_url (/v0/legal-persons/lp.fixture01xxxxxxxxxxxxx))
     (beneficiary_url (/v0/legal-persons/lp.fixture01xxxxxxxxxxxxx))
     (controller_url (/v0/legal-persons/lp.fixture01xxxxxxxxxxxxx))
     (bank_account_product_url (/v0/bank/products/bp.fixture07xxxxxxxxxxxxx))
     (account_transactions_url
      (/v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx/transactions))
     (account_payments_url
      (/v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx/payments))
     (account_admissions_url
      (/v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx/admissions))
     (account_submissions_url
      (/v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx/submissions))
     (created_at (2026-10-13T19:50:49.576Z)))
    (("List.length a.items" 2) ("Option.is_some a.next" true))
    |}]
;;

let%expect_test "transactions, payments, submissions, admissions" =
  let t = page "transactions-inbound" ~key:"account-transactions" (module Transaction) in
  List.iter t.items ~f:(fun t ->
    printf
      "%s %s %s balance=%s\n"
      t.transaction_origin_type
      t.balance_change_direction
      t.balance_change.value
      t.account_balance.value);
  one "payment-outbound" (module Payment);
  let p = page "payments-inbound" ~key:"payments" (module Payment) in
  List.iter p.items ~f:(fun p -> printf "%s %s\n" p.payment_direction p.payment_amount.value);
  one "submission" (module Submission);
  let s = page "submissions" ~key:"submissions" (module Submission) in
  print_s [%message (List.length s.items : int)];
  let a = page "admissions" ~key:"admissions" (module Admission) in
  print_s [%sexp (a : Admission.t Page.t)];
  [%expect {|
    payment credit 12.34 balance=1000012.34
    deposit credit 1000000.00 balance=1000000.00
    ((payment_url /v0/payments/pm.fixture02xxxxxxxxxxxxx)
     (payment_direction outbound-payment) (payment_type (credit-transfer))
     (payment_amount ((currency GBP) (value 12.34)))
     (payment_reference ("fixture inbound"))
     (creditor
      ((creditor_type (uk-domestic))
       (account_holder ("griffin-client fixture B")) (account_number (00000000))
       (account_number_code (bban)) (bank_id (000001)) (bank_id_code (gbdsc))
       (account_url ()) (payee_url ())))
     (debtor
      (((creditor_type ()) (account_holder ("Example Org"))
        (account_number (00000000)) (account_number_code (bban))
        (bank_id (000001)) (bank_id_code (gbdsc))
        (account_url (/v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx))
        (payee_url ()))))
     (payment_submissions_url
      (/v0/payments/pm.fixture02xxxxxxxxxxxxx/submissions))
     (payment_admissions_url ()) (created_at 2026-10-13T19:51:07.600Z))
    inbound-payment 12.34
    ((submission_url /v0/submissions/ps.fixture01xxxxxxxxxxxxx)
     (submission_status delivered)
     (payment_url /v0/payments/pm.fixture02xxxxxxxxxxxxx)
     (created_at 2026-10-13T19:51:08.191Z)
     (account_url (/v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx))
     (submission_scheme_information
      (((payment_scheme fps)
        (end_to_end_identification (5WWPTLUH45NMVGNZTG2DPMPW6A))
        (scheme_status_code ()) (scheme_status_code_description ()))))
     (scheduled_at ()))
    ("List.length s.items" 1)
    ((items
      (((admission_url /v0/admissions/pa.fixture01xxxxxxxxxxxxx)
        (admission_status delivered)
        (payment_url /v0/payments/pm.fixture03xxxxxxxxxxxxx)
        (created_at 2026-10-13T19:51:08.191Z)
        (account_url (/v0/bank/accounts/ba.fixture02xxxxxxxxxxxxx))
        (admission_scheme_information
         (((payment_scheme fps)
           (end_to_end_identification (5WWPTLUH45NMVGNZTG2DPMPW6A))
           (scheme_status_code ()) (scheme_status_code_description ())))))))
     (next ()) (prev ()) (total ()))
    |}]
;;

let%expect_test "payees and confirmation of payee" =
  one "payee" (module Payee);
  let p = page "payees" ~key:"payees" (module Payee) in
  print_s [%message (List.length p.items : int)];
  List.iter [ "cop-match"; "cop-close-match"; "cop-no-match" ] ~f:(fun name ->
    let c = ok_exn (Page.decode Cop_request.t_of_yojson (load name)) in
    print_s [%sexp (c.cop_response : Cop_response.t)]);
  [%expect {|
    ((payee_url /v0/payees/pe.fixture01xxxxxxxxxxxxx)
     (account_holder "Example Payee") (account_number 00000000) (bank_id 040004)
     (payee_status (active))
     (legal_person_url (/v0/legal-persons/lp.fixture01xxxxxxxxxxxxx))
     (cop_request_url (/v0/cop-request/cp.fixture01xxxxxxxxxxxxx))
     (created_at (2026-10-13T19:51:56.434Z)))
    ("List.length p.items" 1)
    ((status verified) (result match) (reason ()) (suggested_name ())
     (suggested_account_classification ()))
    ((status unverified) (result close-match) (reason (close-match-name))
     (suggested_name ("Example Payee CloseMatch"))
     (suggested_account_classification ()))
    ((status unverified) (result no-match) (reason (no-match-name))
     (suggested_name ()) (suggested_account_classification ()))
    |}]
;;

let%expect_test "events and webhooks" =
  let e = page "events" ~key:"events" (module Event) in
  List.iter e.items ~f:(fun e -> print_endline e.event_type);
  print_s [%message (e.next : string option)];
  let w = page "webhooks" ~key:"organization-webhooks" (module Webhook) in
  print_s [%sexp (w.items : Webhook.t list)];
  [%expect {|
    payment-created
    submission-updated
    submission-updated
    transaction-created
    submission-created
    (e.next
     (/v0/organizations/og.fixture01xxxxxxxxxxxxx/events?page[size]=5&page[after]=CURSOR))
    (((webhook_url /v0/webhooks/wh.fixture01xxxxxxxxxxxxx)
      (webhook_destination_url https://example.com/webhook)
      (webhook_state active)
      (webhook_description ("Example webhook"))
      (created_at (2026-09-14T12:45:53.943Z))))
    |}]
;;

let%expect_test "decode errors are short and path-free" =
  print_s
    [%sexp
      (Page.decode Money.t_of_yojson (`Assoc [ "currency", `Int 1 ]) : Money.t Or_error.t)];
  [%expect {| (Error ("unexpected JSON" "string needed" (near 1))) |}]
;;
