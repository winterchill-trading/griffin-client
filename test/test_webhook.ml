open! Core
open Griffin_client
module Sig = Http_signature

let unhex s = Cryptokit.transform_string (Cryptokit.Hexa.decode ()) s
let b64url s = Base64.encode_exn ~pad:false ~alphabet:Base64.uri_safe_alphabet s

(* The throwaway OpenSSL key from test_p521.ml stands in for Griffin's key. *)
let d = unhex Test_p521.d
let kid = "griffin-test-1"

let keys =
  ok_exn
    (Webhook.Keys.of_jwks
       (`Assoc
         [ ( "keys"
           , `List
               [ `Assoc
                   [ "alg", `String "ES512"
                   ; "crv", `String "P-521"
                   ; "kid", `String kid
                   ; "kty", `String "EC"
                   ; "x", `String (b64url (unhex Test_p521.x))
                   ; "y", `String (b64url (unhex Test_p521.y))
                   ]
               ] )
         ]))
;;

let body =
  Yojson.Safe.from_file "fixtures/events.json"
  |> Yojson.Safe.Util.member "events"
  |> Yojson.Safe.Util.index 0
  |> Yojson.Safe.to_string
;;

let created = 1_760_000_000

(* Sign a delivery the way Griffin's documentation shows one. *)
let delivery ?(body = body) ?(sign_body = body) () =
  let headers =
    [ "date", Sig.http_date (Time_ns.of_int_ns_since_epoch (created * 1_000_000_000))
    ; "content-type", "application/json"
    ; "content-length", Int.to_string (String.length body)
    ; "content-digest", Sig.content_digest sign_body
    ]
  in
  let params =
    sprintf
      {|("date" "@method" "@path" "@authority" "content-type" "content-length" "content-digest");created=%d;expires=%d;nonce="2885d616-ff20-42ce-8be4-e5949e5619e4";keyid="%s"|}
      created
      (created + 300)
      kid
  in
  let m =
    { Sig.Message.meth = "POST"
    ; authority = "hooks.example.com"
    ; path = "/griffin"
    ; query = None
    ; headers
    ; body
    }
  in
  let base =
    ok_exn
      (Sig.signature_base
         m
         ~components:
           [ "date"
           ; "@method"
           ; "@path"
           ; "@authority"
           ; "content-type"
           ; "content-length"
           ; "content-digest"
           ]
         ~params)
  in
  let signature = P521.For_testing.sign ~d ~k:(String.make 65 '\003') base in
  headers
  @ [ "signature-input", sprintf "%s=%s" kid params
    ; "signature", sprintf "%s=:%s:" kid (Base64.encode_exn signature)
    ]
;;

let verify ?now ?(body = body) ?(authority = "hooks.example.com") headers =
  Webhook.verify ?now keys ~meth:"post" ~authority ~path:"/griffin" ~headers ~body ()
  |> Result.map ~f:(fun (e : Model.Event.t) -> e.event_type)
;;

let%expect_test "a correctly signed delivery verifies and decodes" =
  print_s [%sexp (verify (delivery ()) : string Or_error.t)];
  [%expect {| (Ok payment-created) |}]
;;

let%expect_test "tampering, wrong host, expiry and unknown keys fail" =
  let tampered = String.substr_replace_first body ~pattern:"1.00" ~with_:"9.00" in
  print_s [%sexp (verify ~body:tampered (delivery ()) : string Or_error.t)];
  (* Body and digest both swapped: the digest matches but the signature does not. *)
  print_s
    [%sexp
      (verify
         ~body:tampered
         (delivery ~body:tampered ~sign_body:body ()
          |> List.map ~f:(fun (k, v) ->
            if String.equal k "content-digest"
            then k, Sig.content_digest tampered
            else k, v))
       : string Or_error.t)];
  print_s [%sexp (verify ~authority:"evil.example.com" (delivery ()) : string Or_error.t)];
  let late = Time_ns.of_int_ns_since_epoch ((created + 301) * 1_000_000_000) in
  print_s [%sexp (verify ~now:late (delivery ()) : string Or_error.t)];
  print_s
    [%sexp
      (Webhook.verify
         Webhook.Keys.empty
         ~meth:"POST"
         ~authority:"hooks.example.com"
         ~path:"/griffin"
         ~headers:(delivery ())
         ~body
         ()
       |> Result.is_ok
       : bool)];
  [%expect
    {|
    (Error "content-digest does not match the body")
    (Error ("signature does not verify" griffin-test-1))
    (Error ("signature does not verify" griffin-test-1))
    (Error ("signature expired" (expires 1760000300)))
    false
    |}]
;;

let%expect_test "Griffin's published keys parse into a key set" =
  let keys =
    ok_exn (Webhook.Keys.of_jwks (Yojson.Safe.from_file "fixtures/public-keys.json"))
  in
  print_s [%sexp (Webhook.Keys.kids keys : string list)];
  [%expect {| (griffin-2026-08-28-1 griffin-2026-09-28-1) |}]
;;
