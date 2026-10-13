open! Core
open! Async
open Griffin_client
open Model

let step name = printf "ok   %s\n%!" name
let fail fmt = ksprintf (fun s -> Deferred.Or_error.error_string s) fmt

let rec poll ?(tries = 30) ~what f =
  match%bind f () with
  | Error _ as e -> return e
  | Ok (Some v) -> return (Ok v)
  | Ok None when tries <= 0 -> fail "timed out waiting for %s" what
  | Ok None ->
    let%bind () = Clock_ns.after (Time_ns.Span.of_sec 1.) in
    poll ~tries:(tries - 1) ~what f
;;

let wait_delivered c (s : Submission.t) =
  poll ~what:"submission delivered" (fun () ->
    let%map.Deferred.Or_error s = Client.submission c s.submission_url in
    match s.submission_status with
    | "delivered" -> Some s
    | "processing" | "scheduled" -> None
    | other -> Some { s with submission_status = "unexpected " ^ other })
;;

let send c account ~creditor ~amount ~reference =
  let open Deferred.Or_error.Let_syntax in
  let%bind p = Client.create_payment c account ~creditor ~amount ~reference in
  match%bind Client.submit_payment c p ~scheme:`Fps with
  | `Already_submitted _ -> fail "fresh payment reported as already submitted"
  | `Submitted s ->
    let%bind s = wait_delivered c s in
    if String.equal s.submission_status "delivered"
    then return (p, s)
    else fail "submission ended %s" s.submission_status
;;

let walk () =
  let open Deferred.Or_error.Let_syntax in
  let%bind config = Deferred.return (Config.of_env ()) in
  let%bind c = Client.connect (Transport.create config) in
  let org = Client.organization c in
  step (sprintf "index -> organization (%s)" org.organization_mode);
  (* Onboarding *)
  let tag = Time_ns.to_int_ns_since_epoch (Time_ns.now ()) / 1_000_000 in
  let%bind lp =
    Client.create_legal_person
      c
      (Claims.sandbox_individual
         ~display_name:(sprintf "LIVETEST, Ada %d" tag)
         ~given_name:"Ada"
         ~surname:"Livetest"
         ~date_of_birth:(Date.of_string "1990-01-01")
         ~email:"livetest@example.com")
  in
  step "create legal person";
  let%bind workflows = Client.workflows c in
  let%bind wf =
    List.find workflows ~f:(fun w ->
      String.equal w.display_name "Individual - Account Owners")
    |> Result.of_option ~error:(Error.of_string "no Individual workflow")
    |> Deferred.return
  in
  let%bind v = Client.start_verification c lp ~workflow_url:wf.workflow_url in
  let%bind v =
    poll ~what:"verification" (fun () ->
      let%map v = Client.verification c v.verification_url in
      match v.verification_status with
      | "pending" | "in-progress" -> None
      | _ -> Some v)
  in
  step (sprintf "verification %s" v.verification_status);
  let%bind decisions = Client.decisions c lp in
  let%bind () =
    match decisions with
    | _ :: _ -> return ()
    | [] ->
      let%map (_ : Decision.t) =
        Client.decide
          c
          lp
          ~verification_url:v.verification_url
          ~outcome:`Accepted
          ~notes:"live test"
      in
      ()
  in
  let%bind lp = Client.legal_person c lp.legal_person_url in
  step
    (sprintf
       "decision: application-status %s"
       (Option.value lp.application_status ~default:"?"));
  (* Accounts *)
  let%bind products = Client.bank_products c in
  let%bind operational =
    List.find products ~f:(fun p ->
      String.equal p.bank_account_product_class "operational")
    |> Result.of_option ~error:(Error.of_string "no operational product")
    |> Deferred.return
  in
  let open_one name =
    let%bind a = Client.open_account c operational ~display_name:name in
    Client.wait_until_open c a
  in
  let%bind a = open_one (sprintf "griffin-client live A %d" tag) in
  let%bind b = open_one (sprintf "griffin-client live B %d" tag) in
  step (sprintf "open operational accounts (A balance %s)" a.account_balance.value);
  (* Inbound payment into B: the sandbox has no simulator for outside senders, so pay B's
     sort code and account number from A over Faster Payments. *)
  let%bind b_address =
    List.hd b.bank_addresses
    |> Result.of_option ~error:(Error.of_string "account B has no bank address")
    |> Deferred.return
  in
  let%bind inbound, _ =
    send
      c
      a
      ~creditor:
        (Uk_domestic
           { account_holder = b_address.account_holder
           ; account_number = b_address.account_number
           ; sort_code = b_address.bank_id
           })
      ~amount:"12.34"
      ~reference:"live inbound"
  in
  step "inbound payment A -> B delivered";
  let%bind txs =
    poll ~what:"credit on B" (fun () ->
      let%map p = Client.transactions c b in
      if List.exists p.items ~f:(fun t ->
           String.equal t.balance_change_direction "credit"
           && String.equal t.balance_change.value "12.34")
      then Some p.items
      else None)
  in
  let%bind admissions = Client.admissions c b in
  step
    (sprintf
       "list transactions on B (%d), admissions (%d)"
       (List.length txs)
       (List.length admissions));
  (* Outbound payment, then the idempotent resubmission. *)
  let%bind out, _ =
    send
      c
      a
      ~creditor:
        (Uk_domestic
           { account_holder = "Example Payee"
           ; account_number = "12345678"
           ; sort_code = "040004"
           })
      ~amount:"5.00"
      ~reference:"live outbound"
  in
  let%bind () =
    match%bind Client.submit_payment c out ~scheme:`Fps with
    | `Already_submitted (_ :: _) -> return ()
    | `Already_submitted [] -> fail "410 but no submissions listed"
    | `Submitted _ -> fail "second submission was accepted"
  in
  step "outbound payment delivered; resubmission answered 410";
  ignore (inbound : Payment.t);
  (* Confirmation of Payee *)
  let check =
    { Client.Cop_check.name = "Example Payee"
    ; account_number = "12345678"
    ; sort_code = "040004"
    ; classification = `Personal
    ; secondary_reference = None
    ; requester_legal_person_url = lp.legal_person_url
    }
  in
  let%bind cop = Client.confirm_payee c check in
  let%bind close = Client.simulate_confirm_payee c check ~outcome:"close-match-name" in
  let%bind () =
    match%bind.Deferred
      Client.simulate_confirm_payee c check ~outcome:"account-not-found"
    with
    | Error e when Option.equal Int.equal (Api_error.status_of_error e) (Some 400) ->
      return ()
    | _ -> fail "account-not-found simulation did not answer 400"
  in
  step
    (sprintf
       "CoP: %s; simulated %s (%s); account-not-found -> 400"
       cop.cop_response.result
       close.cop_response.result
       (Option.value close.cop_response.suggested_name ~default:"-"));
  (* Payee on the organization's own legal person, and a payment to it. *)
  let%bind own =
    Deferred.return
      (Result.of_option
         org.own_legal_person_url
         ~error:(Error.of_string "no own legal person"))
  in
  let%bind own = Client.legal_person c own in
  let%bind payee =
    Client.create_payee
      c
      own
      ~account_holder:"Example Payee"
      ~account_number:"12345678"
      ~sort_code:"040004"
      ~cop_request_url:cop.cop_request_url
  in
  let%bind (_ : Payment.t * Submission.t) =
    send c a ~creditor:(Payee payee.payee_url) ~amount:"1.00" ~reference:"live payee"
  in
  step "payee created and paid";
  (* Events, webhooks, keys, pagination *)
  let%bind events = Client.events ~page_size:20 c in
  let types =
    List.map events.items ~f:(fun e -> e.event_type)
    |> List.dedup_and_sort ~compare:String.compare
  in
  step (sprintf "events: %s" (String.concat ~sep:", " types));
  let%bind hooks = Client.webhooks c in
  let%bind keys = Griffin_client.Webhook.Keys.fetch (Client.transport c) in
  step
    (sprintf
       "webhooks listed (%d, read-only); signing keys %s"
       (List.length hooks)
       (String.concat ~sep:" " (Griffin_client.Webhook.Keys.kids keys)));
  let%bind first =
    Deferred.return
      (Links.find_or_error (Client.links c) "organization-bank-accounts-url")
  in
  let%bind n =
    Client.fold
      c
      (Client.with_page_size first 2)
      ~key:"accounts"
      Bank_account.t_of_yojson
      ~init:0
      ~f:(fun n _ -> n + 1)
  in
  step (sprintf "paged through %d accounts two at a time" n);
  return ()
;;

let () =
  let enabled =
    Config.env_available ()
    && Option.equal String.equal (Sys.getenv "GRIFFIN_LIVE_TESTS") (Some "1")
  in
  if not enabled
  then
    (* Core's, not Async's: the scheduler never starts on this path, so Async's buffered
       stdout would never be flushed. *)
    Core.print_endline
      "griffin live test skipped (set GRIFFIN_API_KEY and GRIFFIN_LIVE_TESTS=1 to run)"
  else
    Command_unix.run
      (Command.async_or_error
         ~summary:"walk the Griffin sandbox"
         (Command.Param.return walk))
;;
