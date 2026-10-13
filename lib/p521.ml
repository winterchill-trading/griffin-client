open! Core

(* secp521r1 domain parameters (SEC 2), as printed by
   [openssl ecparam -name secp521r1 -param_enc explicit -text]. *)
let p = Z.(shift_left one 521 - one)
let a = Z.(p - of_int 3)

let b =
  Z.of_string_base
    16
    "0051953eb9618e1c9a1f929a21a0b68540eea2da725b99b315f3b8b489918ef109e156193951ec7e937b1652c0bd3bb1bf073573df883d2c34f1ef451fd46b503f00"
;;

let n =
  Z.of_string_base
    16
    "01fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffa51868783bf2f966b7fcc0148f709a5d03bb5c9b8899c47aebb6fb71e91386409"
;;

let gx =
  Z.of_string_base
    16
    "00c6858e06b70404e9cd9e3ecb662395b4429c648139053fb521f828af606b4d3dbaa14b5e77efe75928fe1dc127a2ffa8de3348b3c1856a429bf97e7e31c2e5bd66"
;;

let gy =
  Z.of_string_base
    16
    "011839296a789a3bc0045c8a5fb42c7d1bd998f54449579b446817afbd17273e662c97ee72995ef42640c550b9013fad0761353c7086a272c24088be94769fd16650"
;;

let ( %% ) x m = Z.erem x m

type point =
  | Infinity
  | Affine of Z.t * Z.t

let on_curve x y =
  Z.(equal (y * y %% p) (((x * x * x) + (a * x) + b) %% p))
  && Z.(geq x zero && lt x p && geq y zero && lt y p)
;;

let double = function
  | Infinity -> Infinity
  | Affine (x, y) ->
    if Z.(equal y zero)
    then Infinity
    else
      let open Z in
      let l = ((of_int 3 * x * x) + a) * invert (of_int 2 * y) p %% p in
      let x3 = ((l * l) - (of_int 2 * x)) %% p in
      Affine (x3, ((l * (x - x3)) - y) %% p)
;;

let add q r =
  match q, r with
  | Infinity, s | s, Infinity -> s
  | Affine (x1, y1), Affine (x2, y2) ->
    if Z.equal x1 x2
    then if Z.equal y1 y2 then double q else Infinity
    else
      let open Z in
      let l = (y2 - y1) * invert ((x2 - x1) %% p) p %% p in
      let x3 = ((l * l) - x1 - x2) %% p in
      Affine (x3, ((l * (x1 - x3)) - y1) %% p)
;;

let mul k pt =
  let rec go k q acc =
    if Z.(equal k zero)
    then acc
    else go (Z.shift_right k 1) (double q) (if Z.testbit k 0 then add acc q else acc)
  in
  go k pt Infinity
;;

let g = Affine (gx, gy)
let of_be s = Z.of_bits (String.rev s)
let sha512 s = Cryptokit.hash_string (Cryptokit.Hash.sha512 ()) s

let to_be n =
  let s = String.rev (Z.to_bits n) in
  (* Drop the leading zero padding [Z.to_bits] adds up to a machine word. *)
  let s = String.lstrip s ~drop:(Char.equal '\000') in
  if String.is_empty s then "\000" else s
;;

module Public_key = struct
  type t = Z.t * Z.t

  let sexp_of_t (x, _) = [%sexp ("P-521" : string), (Z.format "%x" x : string)]

  let of_coordinates ~x ~y =
    let x = of_be x
    and y = of_be y in
    if on_curve x y then Ok (x, y) else Or_error.error_string "point is not on P-521"
  ;;

  let b64url s =
    match Base64.decode ~pad:false ~alphabet:Base64.uri_safe_alphabet s with
    | Ok v -> Ok v
    | Error (`Msg m) -> Or_error.error_s [%message "bad base64url in JWK" m]
  ;;

  let of_jwk json =
    let open Or_error.Let_syntax in
    let field name =
      match json with
      | `Assoc kv ->
        (match List.Assoc.find kv name ~equal:String.equal with
         | Some (`String s) -> Ok s
         | _ -> Or_error.error_s [%message "JWK field missing" name])
      | _ -> Or_error.error_string "JWK is not an object"
    in
    let%bind kty = field "kty" in
    let%bind crv = field "crv" in
    let%bind () =
      if String.equal kty "EC" && String.equal crv "P-521"
      then Ok ()
      else Or_error.error_s [%message "unsupported JWK" kty crv]
    in
    let%bind kid = field "kid" in
    let%bind x = field "x" >>= b64url in
    let%bind y = field "y" >>= b64url in
    let%map key = of_coordinates ~x ~y in
    kid, key
  ;;
end

(* Minimal DER reader for [SEQUENCE { INTEGER, INTEGER }]. *)
let parse_der s =
  let len = String.length s in
  let byte i = if i < len then Some (Char.to_int s.[i]) else None in
  let read_len i =
    match byte i with
    | Some l when l < 0x80 -> Some (l, i + 1)
    | Some 0x81 -> Option.map (byte (i + 1)) ~f:(fun l -> l, i + 2)
    | Some 0x82 ->
      (match byte (i + 1), byte (i + 2) with
       | Some h, Some l -> Some ((h lsl 8) lor l, i + 3)
       | _ -> None)
    | _ -> None
  in
  let read_int i =
    match byte i with
    | Some 0x02 ->
      Option.bind
        (read_len (i + 1))
        ~f:(fun (l, j) ->
          if j + l <= len then Some (of_be (String.sub s ~pos:j ~len:l), j + l) else None)
    | _ -> None
  in
  match byte 0 with
  | Some 0x30 ->
    Option.bind (read_len 1) ~f:(fun (l, j) ->
      if j + l <> len
      then None
      else
        Option.bind (read_int j) ~f:(fun (r, k) ->
          Option.bind (read_int k) ~f:(fun (s, m) ->
            if m = len then Some (r, s) else None)))
  | _ -> None
;;

let parse_signature s =
  if String.length s = 132
  then Some (of_be (String.prefix s 66), of_be (String.drop_prefix s 66))
  else parse_der s
;;

let verify (qx, qy) ~signature msg =
  match parse_signature signature with
  | None -> false
  | Some (r, s) ->
    let in_range v = Z.(gt v zero && lt v n) in
    in_range r
    && in_range s
    &&
    (* SHA-512 output (512 bits) is shorter than n (521 bits): no truncation. *)
    let e = of_be (sha512 msg) in
    let w = Z.invert s n in
    let u1 = Z.(e * w %% n) in
    let u2 = Z.(r * w %% n) in
    (match add (mul u1 g) (mul u2 (Affine (qx, qy))) with
     | Infinity -> false
     | Affine (x, _) -> Z.equal (x %% n) r)
;;

module For_testing = struct
  let public_key ~d =
    match mul (of_be d) g with
    | Affine (x, y) -> x, y
    | Infinity -> failwith "invalid private scalar"
  ;;

  let der_int v =
    let s = to_be v in
    let s = if Char.to_int s.[0] land 0x80 <> 0 then "\000" ^ s else s in
    "\x02" ^ String.of_char (Char.of_int_exn (String.length s)) ^ s
  ;;

  let sign ~d ~k msg =
    let d = of_be d
    and k = of_be k in
    let e = of_be (sha512 msg) in
    match mul k g with
    | Infinity -> failwith "invalid nonce"
    | Affine (x, _) ->
      let r = x %% n in
      let s = Z.(invert k n * (e + (r * d)) %% n) in
      let body = der_int r ^ der_int s in
      let blen = String.length body in
      let len =
        if blen < 0x80
        then String.of_char (Char.of_int_exn blen)
        else "\x81" ^ String.of_char (Char.of_int_exn blen)
      in
      "\x30" ^ len ^ body
  ;;
end
