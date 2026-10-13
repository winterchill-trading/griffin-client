open! Core
module P521 = Griffin_client.P521

let unhex s = Cryptokit.transform_string (Cryptokit.Hexa.decode ()) s

(* Throwaway key and signature from [openssl ecparam -name secp521r1 -genkey] and
   [openssl dgst -sha512 -sign]. *)
let d =
  "01101adf61e9fd0c620827ede08ef63e993c0371c6239f30db45d52797392568c9fb93ceb125cbc4d9df66c26933e7987ee655a887d4cdec0220b206811ff6217c23"
;;

let x =
  "0140f6ba272ff2d1416b645f21412e33cd5bd15ba62a90499ca819c6237b884d071574cc3694c397d3fa79cf4c3b8e8840591394b3b43c8012fce09d0d4d914b9e43"
;;

let y =
  "00e1b0bf8bfb23f3d2f15f8dbb64e5890edbbb16ab8eabcfe2f969b097bd8419742cf6d152ff4dd51c7592301f90855a51645dcc523b9fa74aa77f7f9ed0136da5c5"
;;

let openssl_sig =
  "MIGHAkIArwzQl8DNQXUUJRkEaONEHgTec98+ktFaJrCeKRWIUEbgzPV3eoxAeaXvArqH+0QiIYSPxIFoWh0h6ZLogUkYOJ8CQUibl1a4mxWV5auVa89tVCvLFP4xFntu55/goVkw3075LutT3VfxyeY1zlAzAynGpMnc3yeLJPeKJYLpCc+JJLWd"
;;

let key = ok_exn (P521.Public_key.of_coordinates ~x:(unhex x) ~y:(unhex y))

let%expect_test "verifies an OpenSSL signature" =
  let signature = Base64.decode_exn openssl_sig in
  print_s
    [%message
      ""
        ~good:(P521.verify key ~signature "griffin webhook body" : bool)
        ~other_msg:(P521.verify key ~signature "griffin webhook bodY" : bool)
        ~garbage:(P521.verify key ~signature:"\x30\x00" "griffin webhook body" : bool)];
  [%expect {| ((good true) (other_msg false) (garbage false)) |}]
;;

let%expect_test "own signatures verify, in DER and raw form" =
  [%test_result: string]
    (Sexp.to_string
       [%sexp (P521.For_testing.public_key ~d:(unhex d) : P521.Public_key.t)])
    ~expect:(Sexp.to_string [%sexp (key : P521.Public_key.t)]);
  let k = String.make 65 '\007' in
  let der = P521.For_testing.sign ~d:(unhex d) ~k "abc" in
  print_s [%message "" ~ok:(P521.verify key ~signature:der "abc" : bool)];
  [%expect {| (ok true) |}]
;;

(* Griffin's published webhook keys (GET /v0/security/public-keys), public data. *)
let%expect_test "parses Griffin's JWKS keys" =
  let json = Yojson.Safe.from_file "fixtures/public-keys.json" in
  let keys = Yojson.Safe.Util.(member "keys" json |> to_list) in
  List.iter keys ~f:(fun k ->
    let kid, _ = ok_exn (P521.Public_key.of_jwk k) in
    print_endline kid);
  [%expect {|
    griffin-2026-09-28-1
    griffin-2026-08-28-1
    |}]
;;

let%expect_test "rejects off-curve points" =
  print_s
    [%sexp
      (P521.Public_key.of_coordinates ~x:(unhex x) ~y:(unhex x) |> Result.is_ok : bool)];
  [%expect {| false |}]
;;
