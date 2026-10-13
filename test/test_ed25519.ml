open! Core
module Ed25519 = Griffin_client.Ed25519

let hex s = Cryptokit.transform_string (Cryptokit.Hexa.encode ()) s
let unhex s = Cryptokit.transform_string (Cryptokit.Hexa.decode ()) s

let check ~seed ~public ~msg ~signature =
  let seed = unhex seed in
  let msg = unhex msg in
  [%test_result: string] (hex (Ed25519.public_key ~seed)) ~expect:public;
  [%test_result: string] (hex (Ed25519.sign ~seed msg)) ~expect:signature;
  [%test_result: bool]
    (Ed25519.verify ~public_key:(unhex public) ~signature:(unhex signature) msg)
    ~expect:true
;;

let%expect_test "RFC 8032 section 7.1 vectors" =
  check
    ~seed:"9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
    ~public:"d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
    ~msg:""
    ~signature:
      "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b";
  check
    ~seed:"4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
    ~public:"3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
    ~msg:"72"
    ~signature:
      "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
;;

(* Signature produced by [openssl pkeyutl -sign -rawin] with the throwaway key from
   test_config.ml over the bytes below. *)
let%expect_test "matches OpenSSL" =
  let msg = "\"@method\": POST\n\"@signature-params\": (\"@method\");created=1" in
  check
    ~seed:"51db3d8c00af0b476c127408d7b456405307c706f4d48844a03163ef61a02e8a"
    ~public:"9b4e7f36c5e246a4a39dc24b071820c3ac3a14036345c6e12a0083d86ed23c55"
    ~msg:(hex msg)
    ~signature:
      "f5ceb3f83963833a3280480244d9ed0955bdc3863c52726570d2cdfb39be1feb5eaad0cbf68ff36f86c57e4e908bcb023a69510dc517b9da5b55ac7673173201"
;;

let%expect_test "tampering fails verification" =
  let seed = String.make 32 'k' in
  let public_key = Ed25519.public_key ~seed in
  let signature = Ed25519.sign ~seed "hello" in
  let flip s i =
    String.mapi s ~f:(fun j c ->
      if j = i then Char.of_int_exn (Char.to_int c lxor 1) else c)
  in
  print_s
    [%message
      ""
        ~ok:(Ed25519.verify ~public_key ~signature "hello" : bool)
        ~msg:(Ed25519.verify ~public_key ~signature "hellp" : bool)
        ~r:(Ed25519.verify ~public_key ~signature:(flip signature 3) "hello" : bool)
        ~s:(Ed25519.verify ~public_key ~signature:(flip signature 40) "hello" : bool)
        ~short:(Ed25519.verify ~public_key ~signature:"x" "hello" : bool)];
  [%expect {| ((ok true) (msg false) (r false) (s false) (short false)) |}]
;;

let%test_unit "sign then verify (quickcheck)" =
  Quickcheck.test
    ~trials:20
    (Quickcheck.Generator.tuple2
       (String.gen_with_length 32 Char.quickcheck_generator)
       String.quickcheck_generator)
    ~f:(fun (seed, msg) ->
      let signature = Ed25519.sign ~seed msg in
      assert (Ed25519.verify ~public_key:(Ed25519.public_key ~seed) ~signature msg))
;;
