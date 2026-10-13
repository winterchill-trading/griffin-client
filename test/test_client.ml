open! Core
open! Async
open Griffin_client
open Model

(* The client against an in-memory Griffin that answers from the recorded fixtures, routed
   by method and path. *)

let org = "/v0/organizations/og.fixture01xxxxxxxxxxxxx"
let file name = In_channel.read_all ("fixtures/" ^ name ^ ".json")

let routes ~mode =
  [ `GET, "/v0/index", (200, file "index")
  ; ( `GET
    , org
    , ( 200
      , String.substr_replace_first (file "organization") ~pattern:"test-mode" ~with_:mode
      ) )
  ; `GET, org ^ "/bank/products", (200, file "bank-products")
  ; `GET, org ^ "/bank/accounts", (200, file "bank-accounts-page")
  ; `GET, org ^ "/events", (200, file "events")
  ; `GET, org ^ "/webhooks", (200, file "webhooks")
  ; `GET, org ^ "/workflows", (200, file "workflows")
  ; `GET, "/v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx", (200, file "bank-account")
  ; ( `GET
    , "/v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx/transactions"
    , (200, file "transactions") )
  ; `POST, "/v0/payments/pm.fixture02xxxxxxxxxxxxx/submissions", (410, file "error-gone")
  ; `GET, "/v0/payments/pm.fixture02xxxxxxxxxxxxx/submissions", (200, file "submissions")
  ; `POST, org ^ "/cop-request", (400, file "cop-account-not-found")
  ; ( `POST
    , "/v0/simulation/organizations/og.fixture01xxxxxxxxxxxxx/cop-request/simulate/close-match-name"
    , (201, file "cop-close-match") )
  ]
;;

let connect ?(mode = "test-mode") ?(live = false) () =
  let table = routes ~mode in
  let log = Queue.create () in
  let send ~meth uri ~headers:_ ~body:_ =
    let path = Uri.path uri in
    Queue.enqueue log (Transport.Meth.to_string meth ^ " " ^ Uri.path_and_query uri);
    return
      (match
         List.find table ~f:(fun (m, p, _) ->
           Transport.Meth.equal m meth && String.equal p path)
       with
       | Some (_, _, (status, body)) ->
         Ok { Transport.Response.status; headers = []; body }
       | None ->
         Ok
           { Transport.Response.status = 404; headers = []; body = file "error-unsigned" })
  in
  let config =
    ok_exn (Config.create ~live ~api_key:(if live then "g-live-x" else "g-test-x") ())
  in
  let%map c = Client.connect (Transport.create ~send config) in
  c, log
;;

let%expect_test "connect follows index -> organization and refuses live mode" =
  let%bind c, log = connect () in
  let c = ok_exn c in
  print_s
    [%message (Client.organization c).display_name (Queue.to_list log : string list)];
  print_s [%sexp (Links.find (Client.links c) "organization-events-url" : string option)];
  let%bind r, _ = connect ~mode:"live-mode" () in
  print_s [%sexp (Result.is_ok r : bool)];
  let%bind r, _ = connect ~mode:"live-mode" ~live:true () in
  print_s [%sexp (Result.is_ok r : bool)];
  [%expect
    {|
    ("Example Org"
     ("Queue.to_list log"
      ("GET /v0/index" "GET /v0/organizations/og.fixture01xxxxxxxxxxxxx")))
    (/v0/organizations/og.fixture01xxxxxxxxxxxxx/events)
    false
    true
    |}];
  return ()
;;

let%expect_test "accounts, transactions, events" =
  let%bind c, log = connect () in
  let c = ok_exn c in
  Queue.clear log;
  let%bind accounts = Client.bank_accounts ~page_size:2 c >>| ok_exn in
  let%bind a =
    Client.bank_account c "/v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx" >>| ok_exn
  in
  let%bind txs = Client.transactions c a >>| ok_exn in
  let%bind events = Client.events c >>| ok_exn in
  let%bind products = Client.bank_products c >>| ok_exn in
  print_s
    [%message
      ""
        ~accounts:(List.length accounts.items : int)
        ~next:(accounts.next : string option)
        ~transactions:(List.length txs.items : int)
        ~events:(List.length events.items : int)
        ~products:(List.length products : int)
        ~requests:(Queue.to_list log : string list)];
  [%expect
    {|
    ((accounts 2)
     (next
      (/v0/organizations/og.fixture01xxxxxxxxxxxxx/bank/accounts?page[size]=2&page[after]=CURSOR))
     (transactions 3) (events 5) (products 10)
     (requests
      ("GET /v0/organizations/og.fixture01xxxxxxxxxxxxx/bank/accounts?page%5Bsize%5D=2"
       "GET /v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx"
       "GET /v0/bank/accounts/ba.fixture01xxxxxxxxxxxxx/transactions"
       "GET /v0/organizations/og.fixture01xxxxxxxxxxxxx/events"
       "GET /v0/organizations/og.fixture01xxxxxxxxxxxxx/bank/products")))
    |}];
  return ()
;;

let%expect_test "a repeated submission (410) lists the payment's submissions" =
  let%bind c, _ = connect () in
  let c = ok_exn c in
  let payment =
    ok_exn
      (Page.decode
         Payment.t_of_yojson
         (Yojson.Safe.from_string (file "payment-outbound")))
  in
  let%bind r = Client.submit_payment c payment ~scheme:`Fps in
  (match ok_exn r with
   | `Submitted _ -> print_endline "submitted"
   | `Already_submitted subs ->
     List.iter subs ~f:(fun s ->
       printf "already: %s %s\n" s.submission_url s.submission_status));
  [%expect {| already: /v0/submissions/ps.fixture01xxxxxxxxxxxxx delivered |}];
  return ()
;;

let%expect_test "CoP errors keep their status; simulations decode" =
  let%bind c, _ = connect () in
  let c = ok_exn c in
  let check =
    { Client.Cop_check.name = "Example Payee"
    ; account_number = "12345678"
    ; sort_code = "040004"
    ; classification = `Personal
    ; secondary_reference = None
    ; requester_legal_person_url = "/v0/legal-persons/lp.fixture02xxxxxxxxxxxxx"
    }
  in
  let%bind r = Client.confirm_payee c check in
  let e = Result.error r |> Option.value_exn in
  print_s [%sexp (Api_error.status_of_error e : int option)];
  let%bind r = Client.simulate_confirm_payee c check ~outcome:"close-match-name" in
  print_s [%sexp ((ok_exn r).cop_response : Cop_response.t)];
  [%expect
    {|
    (400)
    ((status unverified) (result close-match) (reason (close-match-name))
     (suggested_name ("Example Payee CloseMatch"))
     (suggested_account_classification ()))
    |}];
  return ()
;;

let%expect_test "creditor and CoP request bodies" =
  List.iter
    [ Client.Creditor.Uk_domestic
        { account_holder = "Example Payee"
        ; account_number = "12345678"
        ; sort_code = "040004"
        }
    ; Payee "/v0/payees/pe.x"
    ; Griffin_account "/v0/bank/accounts/ba.x"
    ]
    ~f:(fun c -> print_endline (Yojson.Safe.to_string (Client.Creditor.to_json c)));
  print_endline (Client.with_page_size "/v0/x" 500);
  print_endline (Client.with_page_size "/v0/x?sort=created-at" 5);
  [%expect
    {|
    {"creditor-type":"uk-domestic","account-holder":"Example Payee","account-number":"12345678","account-number-code":"bban","bank-id":"040004","bank-id-code":"gbdsc"}
    {"creditor-type":"payee","payee-url":"/v0/payees/pe.x"}
    {"creditor-type":"griffin-bank-account","account-url":"/v0/bank/accounts/ba.x"}
    /v0/x?page[size]=200
    /v0/x?sort=created-at&page[size]=5
    |}];
  return ()
;;
