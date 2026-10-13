open! Core
module Sig = Griffin_client.Http_signature

let seed =
  Cryptokit.transform_string
    (Cryptokit.Hexa.decode ())
    "51db3d8c00af0b476c127408d7b456405307c706f4d48844a03163ef61a02e8a"
;;

let created = Time_ns.of_int_ns_since_epoch 1_724_311_276_000_000_000
let body = {|{"payment-scheme":"fps"}|}

let message =
  Sig.Message.of_uri
    ~meth:"post"
    (Uri.of_string "https://api.griffin.com/v0/payments/pm.abc/submissions?x=1")
    ~headers:
      [ "Content-Type", "application/json"
      ; "Content-Length", Int.to_string (String.length body)
      ; "Date", Sig.http_date created
      ]
    ~body
;;

let%expect_test "date and digest" =
  print_endline (Sig.http_date created);
  print_endline (Sig.content_digest "");
  print_endline (Sig.content_digest body);
  [%expect
    {|
    Thu, 22 Aug 2024 07:21:16 GMT
    sha-512=:z4PhNX7vuL3xVChQ1m2AB9Yg5AULVxXcg/SpIdNs6c5H0NE8XYXysP+DGNKHfuwvY7kxvUdBeoGlODJ6+SfaPg==:
    sha-512=:5hjBs+5UNUn8JGT7yYzxsLZN6h8XGxKqAXHLmhOwTtfx17CzYpbZFHr5grSHeM2JRlDM606a13gA3/BpUZ1ZNw==:
    |}]
;;

let%expect_test "signed request headers and base" =
  let headers =
    ok_exn
      (Sig.sign
         message
         ~key_id:"hs.test"
         ~seed
         ~created
         ~nonce:"019178f6-a7f5-4edb-9ddc-b1488ed84af9")
  in
  List.iter headers ~f:(fun (k, v) -> printf "%s: %s\n" k v);
  [%expect
    {|
    content-digest: sha-512=:5hjBs+5UNUn8JGT7yYzxsLZN6h8XGxKqAXHLmhOwTtfx17CzYpbZFHr5grSHeM2JRlDM606a13gA3/BpUZ1ZNw==:
    signature-input: sig1=("@authority" "content-digest" "content-length" "content-type" "date" "@method" "@path" "@query");alg="ed25519";created=1724311276;expires=1724311576;keyid="hs.test";nonce="019178f6-a7f5-4edb-9ddc-b1488ed84af9"
    signature: sig1=:+jq1dj88eG193RZdSgbvyhOAwWXYTXT/tqb75le1MOmn4hZOrud8pFXkualnjsYmzxH6hwHvnzm+/Qq2/dpMDw==:
    |}];
  let m = { message with headers = message.headers @ headers } in
  let inputs =
    ok_exn
      (Sig.Input.parse
         (List.Assoc.find_exn headers "signature-input" ~equal:String.equal))
  in
  print_s [%sexp (inputs : Sig.Input.t list)];
  [%expect
    {|
    (((label sig1)
      (components
       (@authority content-digest content-length content-type date @method @path
        @query))
      (params
       "(\"@authority\" \"content-digest\" \"content-length\" \"content-type\" \"date\" \"@method\" \"@path\" \"@query\");alg=\"ed25519\";created=1724311276;expires=1724311576;keyid=\"hs.test\";nonce=\"019178f6-a7f5-4edb-9ddc-b1488ed84af9\"")
      (created (1724311276)) (expires (1724311576)) (keyid (hs.test))
      (nonce (019178f6-a7f5-4edb-9ddc-b1488ed84af9)) (alg (ed25519))))
    |}];
  let input = List.hd_exn inputs in
  print_endline
    (ok_exn (Sig.signature_base m ~components:input.components ~params:input.params));
  [%expect
    {|
    "@authority": api.griffin.com
    "content-digest": sha-512=:5hjBs+5UNUn8JGT7yYzxsLZN6h8XGxKqAXHLmhOwTtfx17CzYpbZFHr5grSHeM2JRlDM606a13gA3/BpUZ1ZNw==:
    "content-length": 24
    "content-type": application/json
    "date": Thu, 22 Aug 2024 07:21:16 GMT
    "@method": POST
    "@path": /v0/payments/pm.abc/submissions
    "@query": ?x=1
    "@signature-params": ("@authority" "content-digest" "content-length" "content-type" "date" "@method" "@path" "@query");alg="ed25519";created=1724311276;expires=1724311576;keyid="hs.test";nonce="019178f6-a7f5-4edb-9ddc-b1488ed84af9"
    |}];
  let public_key = Griffin_client.Ed25519.public_key ~seed in
  let check ~keyid:_ ~base ~signature =
    Ok (Griffin_client.Ed25519.verify ~public_key ~signature base)
  in
  print_s
    [%sexp
      (Sig.verify m ~check |> Result.map ~f:(fun i -> i.Sig.Input.label)
       : string Or_error.t)];
  let tampered = { m with body = {|{"payment-scheme":"chaps"}|} } in
  print_s [%sexp (Sig.verify tampered ~check |> Result.is_ok : bool)];
  let late = Time_ns.add created (Time_ns.Span.of_min 6.) in
  print_s [%sexp (Sig.verify ~now:late m ~check |> Result.is_ok : bool)];
  [%expect {|
    (Ok sig1)
    false
    false
    |}]
;;

let%expect_test "parses Griffin's webhook signature-input example" =
  let input =
    {|griffin-2025-05-23-1=("date" "@method" "@path" "@authority" "content-type" "content-length" "content-digest");created=1748006254;expires=1748006554;nonce="2885d616-ff20-42ce-8be4-e5949e5619e4";keyid="griffin-2025-05-23-1"|}
  in
  print_s [%sexp (Sig.Input.parse input : Sig.Input.t list Or_error.t)];
  print_s [%sexp (Sig.Input.parse "x=(\"a\"" : Sig.Input.t list Or_error.t)];
  [%expect
    {|
    (Ok
     (((label griffin-2025-05-23-1)
       (components
        (date @method @path @authority content-type content-length
         content-digest))
       (params
        "(\"date\" \"@method\" \"@path\" \"@authority\" \"content-type\" \"content-length\" \"content-digest\");created=1748006254;expires=1748006554;nonce=\"2885d616-ff20-42ce-8be4-e5949e5619e4\";keyid=\"griffin-2025-05-23-1\"")
       (created (1748006254)) (expires (1748006554))
       (keyid (griffin-2025-05-23-1))
       (nonce (2885d616-ff20-42ce-8be4-e5949e5619e4)) (alg ()))))
    (Error ("malformed signature-input" "expected a component name"))
    |}]
;;

let%expect_test "uuid v4 shape" =
  let u = Sig.uuid_v4 () in
  print_s
    [%message
      ""
        ~length:(String.length u : int)
        ~version:(u.[14] : char)
        ~variant:(String.mem "89ab" u.[19] : bool)];
  [%expect {| ((length 36) (version 4) (variant true)) |}]
;;
