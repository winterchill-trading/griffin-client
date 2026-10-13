open! Core
open! Async
open Griffin_client
open Model

(* Every subcommand connects the same way and prints JSON (default) or sexps. *)
module Out = struct
  type t =
    | Json
    | Sexp

  let flag =
    let%map_open.Command sexp = flag "-sexp" no_arg ~doc:" print sexps instead of JSON" in
    if sexp then Sexp else Json
  ;;

  let print t ~json ~sexp =
    match t with
    | Json -> print_endline (Yojson.Safe.pretty_to_string json)
    | Sexp -> print_s sexp
  ;;

  module type Printable = sig
    type t

    val yojson_of_t : t -> Yojson.Safe.t
    val sexp_of_t : t -> Sexp.t
  end

  let value (type a) t (module M : Printable with type t = a) (v : a) =
    print t ~json:(M.yojson_of_t v) ~sexp:(M.sexp_of_t v)
  ;;

  let list (type a) t (module M : Printable with type t = a) (vs : a list) =
    print t ~json:(`List (List.map vs ~f:M.yojson_of_t)) ~sexp:[%sexp (vs : M.t list)]
  ;;

  let page t m (p : _ Page.t) =
    list t m p.items;
    Option.iter p.next ~f:(fun n -> Print.eprintf "next page: %s\n" n)
  ;;
end

let common =
  let%map_open.Command out = Out.flag
  and verbose = flag "-verbose" no_arg ~doc:" log each HTTP attempt to stderr"
  and live =
    flag "-live" no_arg ~doc:" allow a non-sandbox key and a live organization"
  in
  out, verbose, live
;;

let connect ~verbose ~live =
  let open Deferred.Or_error.Let_syntax in
  let%bind config = Deferred.return (Config.of_env ~live ()) in
  let on_event (e : Transport.Event.t) =
    if verbose then Print.eprint_s [%sexp (e : Transport.Event.t)]
  in
  let transport = Transport.create ~on_event config in
  Client.connect transport
;;

(* Build a command that connects first; [f] gets the client and output format. *)
let cmd ~summary params f =
  Command.async_or_error
    ~summary
    (let%map_open.Command out, verbose, live = common
     and params in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       let%bind client = connect ~verbose ~live in
       f client out params)
;;

let anon_url name = Command.Param.(anon (name %: string))

let page_size =
  Command.Param.(flag "-page-size" (optional int) ~doc:"N items per page (1-200)")
;;

let index =
  cmd
    ~summary:"show the link relations discovered from the index and organization"
    (Command.Param.return ())
    (fun client out () ->
       let links = Client.links client |> Links.to_alist in
       Out.print
         out
         ~json:(`Assoc (List.map links ~f:(fun (k, v) -> k, `String v)))
         ~sexp:[%sexp (links : (string * string) list)];
       Deferred.Or_error.return ())
;;

let org =
  cmd ~summary:"show the organization" (Command.Param.return ()) (fun client out () ->
    Out.value out (module Organization) (Client.organization client);
    Deferred.Or_error.return ())
;;

let legal_persons =
  Command.group
    ~summary:"legal persons and onboarding"
    [ ( "list"
      , cmd ~summary:"list legal persons" page_size (fun c out page_size ->
          let%map.Deferred.Or_error p = Client.legal_persons ?page_size c in
          Out.page out (module Legal_person) p) )
    ; ( "get"
      , cmd
          ~summary:"get a legal person by URL"
          (anon_url "LEGAL-PERSON-URL")
          (fun c out url ->
             let%map.Deferred.Or_error lp = Client.legal_person c url in
             Out.value out (module Legal_person) lp) )
    ; ( "create-sandbox-individual"
      , cmd
          ~summary:"create an individual with sandbox test claims"
          Command.Param.(
            both
              (flag "-given-name" (required string) ~doc:"NAME given name")
              (flag "-surname" (required string) ~doc:"NAME surname"))
          (fun c out (given_name, surname) ->
            let body =
              Claims.sandbox_individual
                ~display_name:(sprintf "%s, %s" (String.uppercase surname) given_name)
                ~given_name
                ~surname
                ~date_of_birth:(Date.of_string "1990-01-01")
                ~email:"test@example.com"
            in
            let%map.Deferred.Or_error lp = Client.create_legal_person c body in
            Out.value out (module Legal_person) lp) )
    ; ( "workflows"
      , cmd
          ~summary:"list onboarding workflows"
          (Command.Param.return ())
          (fun c out () ->
             let%map.Deferred.Or_error w = Client.workflows c in
             Out.list out (module Workflow) w) )
    ; ( "verify"
      , cmd
          ~summary:"start a verification of a legal person"
          Command.Param.(
            both (anon_url "LEGAL-PERSON-URL") (anon ("WORKFLOW-URL" %: string)))
          (fun c out (url, workflow_url) ->
            let open Deferred.Or_error.Let_syntax in
            let%bind lp = Client.legal_person c url in
            let%map v = Client.start_verification c lp ~workflow_url in
            Out.value out (module Verification) v) )
    ; ( "decisions"
      , cmd
          ~summary:"list decisions on a legal person"
          (anon_url "LEGAL-PERSON-URL")
          (fun c out url ->
             let open Deferred.Or_error.Let_syntax in
             let%bind lp = Client.legal_person c url in
             let%map d = Client.decisions c lp in
             Out.list out (module Decision) d) )
    ]
;;

let account_cmd ~summary f =
  cmd ~summary (anon_url "ACCOUNT-URL") (fun c out url ->
    let%bind.Deferred.Or_error a = Client.bank_account c url in
    f c out a)
;;

let accounts =
  Command.group
    ~summary:"bank products and accounts"
    [ ( "products"
      , cmd ~summary:"list bank products" (Command.Param.return ()) (fun c out () ->
          let%map.Deferred.Or_error p = Client.bank_products c in
          Out.list out (module Bank_product) p) )
    ; ( "list"
      , cmd ~summary:"list bank accounts" page_size (fun c out page_size ->
          let%map.Deferred.Or_error p = Client.bank_accounts ?page_size c in
          Out.page out (module Bank_account) p) )
    ; ( "get"
      , account_cmd ~summary:"get a bank account by URL" (fun _ out a ->
          Out.value out (module Bank_account) a;
          Deferred.Or_error.return ()) )
    ; ( "open"
      , cmd
          ~summary:"open an account with a product (by product class or display name)"
          Command.Param.(
            both
              (flag "-product" (required string) ~doc:"NAME e.g. Operational")
              (flag "-name" (required string) ~doc:"NAME account display name"))
          (fun c out (product, name) ->
            let open Deferred.Or_error.Let_syntax in
            let%bind products = Client.bank_products c in
            let%bind p =
              List.find products ~f:(fun p ->
                String.Caseless.equal p.display_name product
                || String.Caseless.equal p.bank_account_product_class product)
              |> Result.of_option
                   ~error:(Error.create_s [%message "no such product" product])
              |> Deferred.return
            in
            let%bind a = Client.open_account c p ~display_name:name in
            let%map a = Client.wait_until_open c a in
            Out.value out (module Bank_account) a) )
    ]
;;

let transactions =
  account_cmd ~summary:"list an account's transactions" (fun c out a ->
    let%map.Deferred.Or_error p = Client.transactions c a in
    Out.page out (module Transaction) p)
;;

let payments =
  Command.group
    ~summary:"payments"
    [ ( "list"
      , account_cmd ~summary:"list an account's payments" (fun c out a ->
          let%map.Deferred.Or_error p = Client.payments c a in
          Out.page out (module Payment) p) )
    ; ( "create"
      , cmd
          ~summary:"create (not send) a GBP payment to a sort code and account number"
          (let%map_open.Command account = anon ("ACCOUNT-URL" %: string)
           and amount = flag "-amount" (required string) ~doc:"GBP e.g. 12.34"
           and sort_code = flag "-sort-code" (required string) ~doc:"DIGITS 6 digits"
           and account_number =
             flag "-account-number" (required string) ~doc:"DIGITS 8 digits"
           and holder = flag "-holder" (required string) ~doc:"NAME account holder"
           and reference =
             flag "-reference" (optional string) ~doc:"TEXT payment reference"
           in
           account, amount, sort_code, account_number, holder, reference)
          (fun c
            out
            (account, amount, sort_code, account_number, account_holder, reference) ->
            let open Deferred.Or_error.Let_syntax in
            let%bind a = Client.bank_account c account in
            let%map p =
              Client.create_payment
                ?reference
                c
                a
                ~amount
                ~creditor:(Uk_domestic { account_holder; account_number; sort_code })
            in
            Out.value out (module Payment) p) )
    ; ( "submit"
      , cmd
          ~summary:"submit a payment over Faster Payments"
          (anon_url "PAYMENT-URL")
          (fun c out url ->
             let open Deferred.Or_error.Let_syntax in
             let%bind p = Client.get c url Payment.t_of_yojson in
             match%map Client.submit_payment c p ~scheme:`Fps with
             | `Submitted s -> Out.value out (module Submission) s
             | `Already_submitted subs ->
               Print.eprintf "already submitted\n";
               Out.list out (module Submission) subs) )
    ; ( "submission"
      , cmd
          ~summary:"get a submission by URL"
          (anon_url "SUBMISSION-URL")
          (fun c out url ->
             let%map.Deferred.Or_error s = Client.submission c url in
             Out.value out (module Submission) s) )
    ]
;;

let cop =
  let check =
    let%map_open.Command name = flag "-name" (required string) ~doc:"NAME payee name"
    and sort_code = flag "-sort-code" (required string) ~doc:"DIGITS 6 digits"
    and account_number = flag "-account-number" (required string) ~doc:"DIGITS 8 digits"
    and business = flag "-business" no_arg ~doc:" business account (default personal)"
    and requester =
      flag "-requester" (optional string) ~doc:"URL legal person asking (default: own)"
    in
    fun client ->
      { Client.Cop_check.name
      ; account_number
      ; sort_code
      ; classification = (if business then `Business else `Personal)
      ; secondary_reference = None
      ; requester_legal_person_url =
          Option.first_some requester (Client.organization client).own_legal_person_url
          |> Option.value ~default:""
      }
  in
  Command.group
    ~summary:"Confirmation of Payee"
    [ ( "check"
      , cmd
          ~summary:"check a payee's name against their account"
          check
          (fun c out check ->
             let%map.Deferred.Or_error r = Client.confirm_payee c (check c) in
             Out.value out (module Cop_request) r) )
    ; ( "simulate"
      , cmd
          ~summary:"sandbox: force a CoP outcome (full-match, close-match-name, ...)"
          Command.Param.(
            both check (flag "-outcome" (required string) ~doc:"TYPE outcome"))
          (fun c out (check, outcome) ->
            let%map.Deferred.Or_error r =
              Client.simulate_confirm_payee c (check c) ~outcome
            in
            Out.value out (module Cop_request) r) )
    ]
;;

let events =
  cmd ~summary:"list organization events (newest first)" page_size (fun c out page_size ->
    let%map.Deferred.Or_error p = Client.events ?page_size c in
    Out.page out (module Event) p)
;;

let webhooks =
  cmd
    ~summary:"list the organization's webhook (read-only)"
    (Command.Param.return ())
    (fun c out () ->
       let%map.Deferred.Or_error w = Client.webhooks c in
       Out.list out (module Webhook) w)
;;

let keys =
  cmd
    ~summary:"list Griffin's webhook signing key ids"
    (Command.Param.return ())
    (fun c out () ->
       let%map.Deferred.Or_error k =
         Griffin_client.Webhook.Keys.fetch (Client.transport c)
       in
       let kids = Griffin_client.Webhook.Keys.kids k in
       Out.print
         out
         ~json:(`List (List.map kids ~f:(fun k -> `String k)))
         ~sexp:[%sexp (kids : string list)])
;;

(* Does not connect first: with an unregistered key every other call is rejected. *)
let check_signature =
  Command.async_or_error
    ~summary:"send a signed request to Griffin's signature debug endpoint"
    (let%map_open.Command _out, verbose, live = common in
     fun () ->
       let open Deferred.Or_error.Let_syntax in
       let%bind config = Deferred.return (Config.of_env ~live ()) in
       let%bind () =
         if Option.is_some config.signing
         then return ()
         else
           Deferred.Or_error.error_string
             "set GRIFFIN_SIGNING_KEY and GRIFFIN_SIGNING_KEY_ID"
       in
       let on_event (e : Transport.Event.t) =
         if verbose then Print.eprint_s [%sexp (e : Transport.Event.t)]
       in
       let%map r, _ =
         Transport.call
           (Transport.create ~on_event config)
           `POST
           "/v0/security/message-signature/verify"
           ~body:(`Assoc [ "hello", `String "griffin" ])
           ()
       in
       printf "%d %s\n" r.status r.body)
;;

let () =
  Command.group
    ~summary:"Griffin banking API client (sandbox by default)"
    ~readme:(fun () ->
      "Reads GRIFFIN_API_KEY, GRIFFIN_API_BASE_URL and optionally GRIFFIN_SIGNING_KEY and\n\
       GRIFFIN_SIGNING_KEY_ID from the environment. URLs are the links Griffin returns,\n\
       e.g. /v0/bank/accounts/ba.xxx.")
    [ "index", index
    ; "org", org
    ; "legal-persons", legal_persons
    ; "accounts", accounts
    ; "transactions", transactions
    ; "payments", payments
    ; "cop", cop
    ; "events", events
    ; "webhooks", webhooks
    ; "keys", keys
    ; "check-signature", check_signature
    ]
  |> Command_unix.run
;;
