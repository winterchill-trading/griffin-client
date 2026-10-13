open! Core
open! Async
module T = Griffin_client.Transport

let config ?signing () =
  ok_exn (Griffin_client.Config.create ?signing ~api_key:"g-test-SECRETKEY" ())
;;

(* A scripted server: answers in order, records what it was asked. *)
let fake responses =
  let queue = Queue.of_list responses in
  let seen = Queue.create () in
  let send ~meth uri ~headers ~body =
    Queue.enqueue seen (meth, uri, headers, body);
    return
      (match Queue.dequeue queue with
       | Some (`Status (status, body)) -> Ok { T.Response.status; headers = []; body }
       | Some `Fail -> Or_error.error_string "connection reset"
       | None -> Or_error.error_string "no scripted response")
  in
  send, seen
;;

let transport ?signing responses =
  let send, seen = fake responses in
  let sleeps = Queue.create () in
  let t =
    T.create
      ~send
      ~sleep:(fun span ->
        Queue.enqueue sleeps span;
        return ())
      ~now:(fun () -> Time_ns.of_int_ns_since_epoch 1_760_000_000_000_000_000)
      (config ?signing ())
  in
  t, seen, sleeps
;;

let%expect_test "GET retries 429 and 503, then succeeds" =
  let t, seen, sleeps =
    transport
      [ `Status (429, ""); `Fail; `Status (503, "busy"); `Status (200, {|{"a":1}|}) ]
  in
  let%bind r = T.json t `GET "/v0/index" () in
  print_s [%sexp (Or_error.map r ~f:Yojson.Safe.to_string : string Or_error.t)];
  print_s
    [%message (Queue.length seen : int) (Queue.to_list sleeps : Time_ns.Span.t list)];
  [%expect
    {|
    (Ok "{\"a\":1}")
    (("Queue.length seen" 4) ("Queue.to_list sleeps" (250ms 500ms 1s)))
    |}];
  return ()
;;

let%expect_test "POST is not retried unless idempotent" =
  let t, seen, _ = transport [ `Status (503, ""); `Status (201, "{}") ] in
  let%bind r = T.json t `POST "/v0/bank/accounts/ba.x/payments" ~body:(`Assoc []) () in
  print_s [%message (Result.is_ok r : bool) (Queue.length seen : int)];
  let t, seen, _ = transport [ `Status (503, ""); `Status (201, "{}") ] in
  let%bind r =
    T.json ~idempotent:true t `POST "/v0/payments/pm.x/submissions" ~body:(`Assoc []) ()
  in
  print_s [%message (Result.is_ok r : bool) (Queue.length seen : int)];
  [%expect
    {|
    (("Result.is_ok r" false) ("Queue.length seen" 1))
    (("Result.is_ok r" true) ("Queue.length seen" 2))
    |}];
  return ()
;;

let strip_request_id = function
  | Sexp.List [ Sexp.Atom "request_id"; _ ] ->
    Sexp.List [ Sexp.Atom "request_id"; Atom "<id>" ]
  | s -> s
;;

let rec map_sexp f = function
  | Sexp.Atom _ as a -> f a
  | Sexp.List l -> f (Sexp.List (List.map l ~f:(map_sexp f)))
;;

let%expect_test "errors decode Griffin bodies and never show the key" =
  let t, _, _ =
    transport
      [ `Status
          ( 401
          , {|{"errors":[{"title":"Unauthorized","status":"401","detail":["content-digest","date"],"code":"missing-required-components"}]}|}
          )
      ; `Status (400, "bad key g-test-SECRETKEY")
      ]
  in
  let%bind r = T.json t `POST "/v0/security/message-signature/verify" ~body:`Null () in
  let e = Result.error r |> Option.value_exn in
  print_s (map_sexp strip_request_id (Error.sexp_of_t e));
  print_s [%sexp (Griffin_client.Api_error.status_of_error e : int option)];
  let%bind r = T.json t `POST "/v0/x" () in
  print_s
    (map_sexp strip_request_id (Error.sexp_of_t (Result.error r |> Option.value_exn)));
  [%expect
    {|
    ("griffin http error"
     ((meth POST) (path /v0/security/message-signature/verify) (status 401)
      (request_id <id>)
      (problems
       (((title (Unauthorized)) (status (401))
         (detail ("[\"content-digest\",\"date\"]"))
         (code (missing-required-components)))))
      (body "")))
    (401)
    ("griffin http error"
     ((meth POST) (path /v0/x) (status 400) (request_id <id>) (problems ())
      (body "bad key <redacted>")))
    |}];
  return ()
;;

let%expect_test "headers: key, and RFC 9421 signature when configured" =
  let seed = String.make 32 's' in
  let signing =
    { Griffin_client.Config.Signing.key_id = "hs.k"
    ; private_key = Griffin_client.Secret.of_string seed
    }
  in
  let t, seen, _ = transport ~signing [ `Status (204, "") ] in
  let%bind r = T.unit t `GET "/v0/ping" () in
  print_s [%sexp (r : unit Or_error.t)];
  let _, uri, headers, _ = Queue.dequeue_exn seen in
  print_endline (Uri.to_string uri);
  List.iter headers ~f:(fun (k, v) ->
    let v =
      match k with
      | "authorization" -> String.prefix v 20 ^ "..."
      | "x-request-id" -> "<uuid>"
      | "signature-input" ->
        String.substr_replace_all
          v
          ~pattern:(String.sub v ~pos:(String.length v - 37) ~len:36)
          ~with_:"<nonce>"
      | "signature" -> "<sig>"
      | _ -> v
    in
    printf "%s: %s\n" k v);
  [%expect
    {|
    (Ok ())
    https://api.griffin.com/v0/ping
    authorization: GriffinAPIKey g-test...
    accept: application/json
    x-request-id: <uuid>
    content-type: application/json
    content-length: 0
    date: Thu, 09 Oct 2025 08:53:20 GMT
    content-digest: sha-512=:z4PhNX7vuL3xVChQ1m2AB9Yg5AULVxXcg/SpIdNs6c5H0NE8XYXysP+DGNKHfuwvY7kxvUdBeoGlODJ6+SfaPg==:
    signature-input: sig1=("@authority" "content-digest" "content-length" "content-type" "date" "@method" "@path" "@query");alg="ed25519";created=1760000000;expires=1760000300;keyid="hs.k";nonce="<nonce>"
    signature: <sig>
    |}];
  return ()
;;

let%expect_test "resolve keeps Griffin's query text and refuses other hosts" =
  let t, _, _ = transport [] in
  let show s =
    print_s [%sexp (T.resolve t s |> Or_error.map ~f:Uri.to_string : string Or_error.t)]
  in
  show "/v0/organizations/og.1/events?page[size]=2&page[after]=djE6FT_35";
  show "https://api.griffin.com/v0/index";
  show "https://evil.example/v0/index";
  show "v0/index";
  [%expect
    {|
    (Ok
     https://api.griffin.com/v0/organizations/og.1/events?page%5Bsize%5D=2&page%5Bafter%5D=djE6FT_35)
    (Ok https://api.griffin.com/v0/index)
    (Error ("refusing to send the API key to another host" evil.example))
    (Error ("link must start with /" v0/index))
    |}];
  return ()
;;

let%expect_test "backoff" =
  List.iter [ 1; 2; 3; 6; 9 ] ~f:(fun attempt ->
    print_s [%sexp (T.backoff ~attempt ~retry_after:None : Time_ns.Span.t)]);
  print_s [%sexp (T.backoff ~attempt:1 ~retry_after:(Some "3") : Time_ns.Span.t)];
  [%expect {|
    250ms
    500ms
    1s
    8s
    8s
    3s
    |}];
  return ()
;;
