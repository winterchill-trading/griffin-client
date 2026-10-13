open! Core
open! Async
open Model

type t =
  { transport : Transport.t
  ; organization : Organization.t
  ; links : Links.t
  }

let transport t = t.transport
let organization t = t.organization
let links t = t.links
let decode = Page.decode
let get t link f = Transport.json t.transport `GET link () >>| Or_error.bind ~f:(decode f)

let connect transport =
  let open Deferred.Or_error.Let_syntax in
  let%bind index = Index.fetch transport in
  let%bind org_url = Deferred.return (Links.find_or_error index "organization-url") in
  let%bind org_json = Transport.json transport `GET org_url () in
  let%bind organization = Deferred.return (decode Organization.t_of_yojson org_json) in
  let%bind () =
    if String.equal organization.organization_mode "test-mode"
       || (Transport.config transport).live
    then return ()
    else
      Deferred.Or_error.error_s
        [%message
          "organization is not a sandbox; create the config with ~live:true"
            ~mode:(organization.organization_mode : string)]
  in
  return { transport; organization; links = Links.merge index (Links.of_json org_json) }
;;

let with_page_size link n =
  let sep = if String.mem link '?' then "&" else "?" in
  sprintf "%s%spage[size]=%d" link sep (Int.clamp_exn n ~min:1 ~max:200)
;;

let page t link ~key f =
  Transport.json t.transport `GET link () >>| Or_error.bind ~f:(Page.of_json ~key f)
;;

let fold t link ~key f ~init ~f:step =
  let rec loop link acc =
    match%bind page t link ~key f with
    | Error _ as e -> return e
    | Ok p ->
      let acc = List.fold p.items ~init:acc ~f:step in
      (match p.next with
       | None -> return (Ok acc)
       | Some next -> loop next acc)
  in
  loop link init
;;

let pipe t link ~key f =
  Pipe.create_reader ~close_on_exception:true (fun writer ->
    let rec loop link =
      match%bind page t link ~key f with
      | Error _ as e -> Pipe.write_if_open writer e
      | Ok p ->
        let%bind () =
          Deferred.List.iter ~how:`Sequential p.items ~f:(fun x ->
            Pipe.write_if_open writer (Ok x))
        in
        (match p.next with
         | Some next when not (Pipe.is_closed writer) -> loop next
         | _ -> return ())
    in
    loop link)
;;

let all t link ~key f =
  fold t link ~key f ~init:[] ~f:(fun acc x -> x :: acc) >>| Or_error.map ~f:List.rev
;;

let org_link t rel = Links.find_or_error t.links rel |> Deferred.return

let need name = function
  | Some v -> Ok v
  | None -> Or_error.error_s [%message "resource has no link" name]
;;

let sized ?page_size link =
  match page_size with
  | None -> link
  | Some n -> with_page_size link n
;;

let post t ?idempotent link body f =
  Transport.json ?idempotent t.transport `POST link ~body ()
  >>| Or_error.bind ~f:(decode f)
;;

(* Onboarding *)

let workflows t =
  let open Deferred.Or_error.Let_syntax in
  let%bind link = org_link t "organization-workflows-url" in
  all t link ~key:"workflows" Workflow.t_of_yojson
;;

let legal_persons ?page_size t =
  let open Deferred.Or_error.Let_syntax in
  let%bind link = org_link t "organization-legal-persons-url" in
  page t (sized ?page_size link) ~key:"legal-persons" Legal_person.t_of_yojson
;;

let legal_person t url = get t url Legal_person.t_of_yojson

let create_legal_person t body =
  let open Deferred.Or_error.Let_syntax in
  let%bind link = org_link t "organization-legal-persons-url" in
  post t link body Legal_person.t_of_yojson
;;

let start_verification t (lp : Legal_person.t) ~workflow_url =
  let open Deferred.Or_error.Let_syntax in
  let%bind link =
    Deferred.return
      (need "legal-person-verifications-url" lp.legal_person_verifications_url)
  in
  post t link (`Assoc [ "workflow-url", `String workflow_url ]) Verification.t_of_yojson
;;

let verification t url = get t url Verification.t_of_yojson

let decisions t (lp : Legal_person.t) =
  let open Deferred.Or_error.Let_syntax in
  let%bind link =
    Deferred.return (need "legal-person-decisions-url" lp.legal_person_decisions_url)
  in
  all t link ~key:"decisions" Decision.t_of_yojson
;;

let decide t (lp : Legal_person.t) ~verification_url ~outcome ~notes =
  let open Deferred.Or_error.Let_syntax in
  let%bind () =
    if String.equal t.organization.organization_mode "test-mode"
    then return ()
    else Deferred.Or_error.error_string "decisions are made by Griffin in live mode"
  in
  let%bind link =
    Deferred.return (need "legal-person-decisions-url" lp.legal_person_decisions_url)
  in
  let outcome =
    match outcome with
    | `Accepted -> "accepted"
    | `Declined -> "declined"
  in
  post
    t
    link
    (`Assoc
      [ "verification-url", `String verification_url
      ; "decision-outcome", `String outcome
      ; "decision-notes", `String notes
      ])
    Decision.t_of_yojson
;;

(* Accounts *)

let bank_products t =
  let open Deferred.Or_error.Let_syntax in
  let%bind link = org_link t "organization-bank-account-products-url" in
  all t link ~key:"bank-account-products" Bank_product.t_of_yojson
;;

let bank_accounts ?page_size t =
  let open Deferred.Or_error.Let_syntax in
  let%bind link = org_link t "organization-bank-accounts-url" in
  page t (sized ?page_size link) ~key:"accounts" Bank_account.t_of_yojson
;;

let bank_account t url = get t url Bank_account.t_of_yojson

let open_account ?owner_url ?beneficiary_url t (product : Bank_product.t) ~display_name =
  let opt k = Option.map ~f:(fun v -> k, `String v) in
  let body =
    `Assoc
      (List.filter_opt
         [ Some ("display-name", `String display_name)
         ; opt "owner-url" owner_url
         ; opt "beneficiary-url" beneficiary_url
         ])
  in
  post t product.bank_account_product_accounts_url body Bank_account.t_of_yojson
;;

let wait_until_open
  ?(interval = Time_ns.Span.of_sec 1.)
  ?(tries = 60)
  t
  (a : Bank_account.t)
  =
  let rec loop n (a : Bank_account.t) =
    if String.equal a.account_status "open"
    then return (Ok a)
    else if n >= tries
    then
      Deferred.Or_error.error_s
        [%message "account did not open" a.account_url ~status:a.account_status]
    else (
      let%bind () = Clock_ns.after interval in
      match%bind bank_account t a.account_url with
      | Error _ as e -> return e
      | Ok a -> loop (n + 1) a)
  in
  loop 0 a
;;

let transactions ?page_size t (a : Bank_account.t) =
  let open Deferred.Or_error.Let_syntax in
  let%bind link =
    Deferred.return (need "account-transactions-url" a.account_transactions_url)
  in
  page t (sized ?page_size link) ~key:"account-transactions" Transaction.t_of_yojson
;;

(* Payments *)

module Creditor = struct
  type t =
    | Uk_domestic of
        { account_holder : string
        ; account_number : string
        ; sort_code : string
        }
    | Payee of string
    | Griffin_account of string
  [@@deriving sexp_of]

  let to_json = function
    | Uk_domestic { account_holder; account_number; sort_code } ->
      `Assoc
        [ "creditor-type", `String "uk-domestic"
        ; "account-holder", `String account_holder
        ; "account-number", `String account_number
        ; "account-number-code", `String "bban"
        ; "bank-id", `String sort_code
        ; "bank-id-code", `String "gbdsc"
        ]
    | Payee url -> `Assoc [ "creditor-type", `String "payee"; "payee-url", `String url ]
    | Griffin_account url ->
      `Assoc
        [ "creditor-type", `String "griffin-bank-account"; "account-url", `String url ]
  ;;
end

let create_payment ?reference t (a : Bank_account.t) ~creditor ~amount =
  let open Deferred.Or_error.Let_syntax in
  let%bind link = Deferred.return (need "account-payments-url" a.account_payments_url) in
  let body =
    `Assoc
      ([ "creditor", Creditor.to_json creditor
       ; "payment-amount", `Assoc [ "currency", `String "GBP"; "value", `String amount ]
       ]
       @
       match reference with
       | None -> []
       | Some r -> [ "payment-reference", `String r ])
  in
  post t link body Payment.t_of_yojson
;;

let submission t url = get t url Submission.t_of_yojson

let submit_payment t (p : Payment.t) ~scheme =
  let open Deferred.Or_error.Let_syntax in
  let%bind link =
    Deferred.return (need "payment-submissions-url" p.payment_submissions_url)
  in
  let scheme =
    match scheme with
    | `Fps -> "fps"
    | `Book_transfer -> "book-transfer"
  in
  match%bind.Deferred
    post
      t
      ~idempotent:true
      link
      (`Assoc [ "payment-scheme", `String scheme ])
      Submission.t_of_yojson
  with
  | Ok s -> return (`Submitted s)
  | Error e when Option.equal Int.equal (Api_error.status_of_error e) (Some 410) ->
    let%map subs = all t link ~key:"submissions" Submission.t_of_yojson in
    `Already_submitted subs
  | Error e -> Deferred.return (Error e)
;;

let payments ?page_size t (a : Bank_account.t) =
  let open Deferred.Or_error.Let_syntax in
  let%bind link = Deferred.return (need "account-payments-url" a.account_payments_url) in
  page t (sized ?page_size link) ~key:"payments" Payment.t_of_yojson
;;

let admissions t (a : Bank_account.t) =
  let open Deferred.Or_error.Let_syntax in
  let%bind link =
    Deferred.return (need "account-admissions-url" a.account_admissions_url)
  in
  all t link ~key:"admissions" Admission.t_of_yojson
;;

(* Payees and CoP *)

let payees t (lp : Legal_person.t) =
  let open Deferred.Or_error.Let_syntax in
  let%bind link =
    Deferred.return (need "legal-person-bank-payees-url" lp.legal_person_bank_payees_url)
  in
  all t link ~key:"payees" Payee.t_of_yojson
;;

let create_payee
  ?cop_request_url
  t
  (lp : Legal_person.t)
  ~account_holder
  ~account_number
  ~sort_code
  =
  let open Deferred.Or_error.Let_syntax in
  let%bind link =
    Deferred.return (need "legal-person-bank-payees-url" lp.legal_person_bank_payees_url)
  in
  let body =
    `Assoc
      ([ "account-holder", `String account_holder
       ; "account-number", `String account_number
       ; "bank-id", `String sort_code
       ]
       @
       match cop_request_url with
       | None -> []
       | Some u -> [ "cop-request-url", `String u ])
  in
  post t link body Payee.t_of_yojson
;;

module Cop_check = struct
  type t =
    { name : string
    ; account_number : string
    ; sort_code : string
    ; classification : [ `Personal | `Business ]
    ; secondary_reference : string option
    ; requester_legal_person_url : string
    }
  [@@deriving sexp_of]

  let to_json t =
    `Assoc
      ([ "name", `String t.name
       ; "account-number", `String t.account_number
       ; "bank-id", `String t.sort_code
       ; ( "account-classification"
         , `String
             (match t.classification with
              | `Personal -> "personal"
              | `Business -> "business") )
       ; "requester-legal-person-url", `String t.requester_legal_person_url
       ]
       @
       match t.secondary_reference with
       | None -> []
       | Some r -> [ "secondary-reference-data", `String r ])
  ;;
end

(* No resource links to these two endpoints; they hang off the organization path. *)
let confirm_payee t check =
  post
    t
    (t.organization.organization_url ^ "/cop-request")
    (Cop_check.to_json check)
    Cop_request.t_of_yojson
;;

let simulate_confirm_payee t check ~outcome =
  let org = t.organization.organization_url in
  let suffix = String.chop_prefix_if_exists org ~prefix:"/v0" in
  post
    t
    (sprintf "/v0/simulation%s/cop-request/simulate/%s" suffix outcome)
    (Cop_check.to_json check)
    Cop_request.t_of_yojson
;;

(* Events and webhooks *)

let events ?page_size t =
  let open Deferred.Or_error.Let_syntax in
  let%bind link = org_link t "organization-events-url" in
  page t (sized ?page_size link) ~key:"events" Event.t_of_yojson
;;

let webhooks t =
  let open Deferred.Or_error.Let_syntax in
  let%bind link = org_link t "organization-webhooks-url" in
  all t link ~key:"organization-webhooks" Webhook.t_of_yojson
;;
