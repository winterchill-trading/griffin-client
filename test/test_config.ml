open! Core

let env pairs name = List.Assoc.find pairs name ~equal:String.equal

let show pairs =
  match Griffin_client.Config.of_env ~getenv:(env pairs) () with
  | Ok t -> print_s [%sexp (t : Griffin_client.Config.t)]
  | Error e -> print_s [%sexp (e : Error.t)]
;;

let%expect_test "sandbox key from env, secrets never print" =
  show [ "GRIFFIN_API_KEY", "g-test-abc123" ];
  [%expect
    {|
    ((base_url https://api.griffin.com) (api_key <redacted>) (signing ())
     (live false))
    |}]
;;

let%expect_test "missing or non-sandbox key" =
  show [];
  [%expect {| "GRIFFIN_API_KEY is not set" |}];
  show [ "GRIFFIN_API_KEY", "g-live-abc" ];
  [%expect {| "API key is not a sandbox (g-test-) key; pass ~live:true to use it" |}];
  show [ "GRIFFIN_API_KEY", "g-test-x"; "GRIFFIN_SIGNING_KEY_ID", "hs.1" ];
  [%expect {| "set both GRIFFIN_SIGNING_KEY and GRIFFIN_SIGNING_KEY_ID, or neither" |}]
;;

(* Generated with [openssl genpkey -algorithm ed25519]; a throwaway test key. *)
let pem =
  {|-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIFHbPYwArwtHbBJ0CNe0VkBTB8cG9NSIRKAxY+9hoC6K
-----END PRIVATE KEY-----|}
;;

let%expect_test "signing key formats" =
  let seed = ok_exn (Griffin_client.Config.parse_ed25519_private_key pem) in
  let hex = Cryptokit.transform_string (Cryptokit.Hexa.encode ()) seed in
  print_endline hex;
  [%expect {| 51db3d8c00af0b476c127408d7b456405307c706f4d48844a03163ef61a02e8a |}];
  let b64 = Base64.encode_exn seed in
  [%test_result: string]
    (ok_exn (Griffin_client.Config.parse_ed25519_private_key hex))
    ~expect:seed;
  [%test_result: string]
    (ok_exn (Griffin_client.Config.parse_ed25519_private_key b64))
    ~expect:seed;
  show
    [ "GRIFFIN_API_KEY", "g-test-x"
    ; "GRIFFIN_SIGNING_KEY", pem
    ; "GRIFFIN_SIGNING_KEY_ID", "hs.key"
    ];
  [%expect
    {|
    ((base_url https://api.griffin.com) (api_key <redacted>)
     (signing (((key_id hs.key) (private_key <redacted>)))) (live false))
    |}];
  print_s
    [%sexp (Griffin_client.Config.parse_ed25519_private_key "nope" : string Or_error.t)];
  [%expect
    {| (Error "signing key must be a PKCS#8 PEM or a 32-byte seed in base64 or hex") |}]
;;
