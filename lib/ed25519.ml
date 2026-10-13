open! Core

let p = Z.(shift_left one 255 - of_int 19)
let l = Z.(shift_left one 252 + of_string "27742317777372353535851937790883648493")
let ( %% ) a m = Z.erem a m
let inv x = Z.invert x p
let d = Z.(of_int (-121665) * inv (of_int 121666) %% p)
let sqrt_m1 = Z.powm Z.(of_int 2) Z.((p - one) / of_int 4) p
let sha512 s = Cryptokit.hash_string (Cryptokit.Hash.sha512 ()) s

(* Little-endian bytes <-> integer. [Z.to_bits] pads to a machine word, so cut or pad to
   the wanted width. *)
let of_le s = Z.of_bits s

let to_le n ~len =
  let b = Z.to_bits n in
  if String.length b >= len
  then String.prefix b len
  else b ^ String.make (len - String.length b) '\000'
;;

(* Extended homogeneous coordinates (X : Y : Z : T), x = X/Z, y = Y/Z, xy = T/Z. *)
type point =
  { x : Z.t
  ; y : Z.t
  ; z : Z.t
  ; t : Z.t
  }

let add a b =
  let open Z in
  let a_ = (a.y - a.x) * (b.y - b.x) %% p in
  let b_ = (a.y + a.x) * (b.y + b.x) %% p in
  let c = a.t * of_int 2 * d * b.t %% p in
  let d_ = a.z * of_int 2 * b.z %% p in
  let e = b_ - a_ in
  let f = d_ - c in
  let g = d_ + c in
  let h = b_ + a_ in
  { x = e * f %% p; y = g * h %% p; t = e * h %% p; z = f * g %% p }
;;

let identity = { x = Z.zero; y = Z.one; z = Z.one; t = Z.zero }

let mul s pt =
  let rec go s q acc =
    if Z.(equal s zero)
    then acc
    else (
      let acc = if Z.testbit s 0 then add acc q else acc in
      go (Z.shift_right s 1) (add q q) acc)
  in
  go s pt identity
;;

let equal_point a b =
  Z.(equal (a.x * b.z %% p) (b.x * a.z %% p))
  && Z.(equal (a.y * b.z %% p) (b.y * a.z %% p))
;;

let recover_x y x_odd =
  if Z.geq y p
  then None
  else
    let open Z in
    let x2 = ((y * y) - one) * inv ((d * y * y) + one) %% p in
    if equal x2 zero
    then if x_odd then None else Some zero
    else (
      let x = powm x2 ((p + of_int 3) / of_int 8) p in
      let x = if equal (((x * x) - x2) %% p) zero then x else x * sqrt_m1 %% p in
      if not (equal (((x * x) - x2) %% p) zero)
      then None
      else (
        let x = if Bool.equal (testbit x 0) x_odd then x else p - x in
        Some x))
;;

let base =
  let y = Z.(of_int 4 * inv (of_int 5) %% p) in
  let x = Option.value_exn (recover_x y false) in
  { x; y; z = Z.one; t = Z.(x * y %% p) }
;;

let encode pt =
  let zi = inv pt.z in
  let x = Z.(pt.x * zi %% p) in
  let y = Z.(pt.y * zi %% p) in
  let v = if Z.testbit x 0 then Z.(y lor shift_left one 255) else y in
  to_le v ~len:32
;;

let decode s =
  if String.length s <> 32
  then None
  else (
    let v = of_le s in
    let sign = Z.testbit v 255 in
    let y = Z.(v land (shift_left one 255 - one)) in
    Option.map (recover_x y sign) ~f:(fun x -> { x; y; z = Z.one; t = Z.(x * y %% p) }))
;;

let expand seed =
  let h = sha512 seed in
  let a = of_le (String.prefix h 32) in
  (* Clamp: clear the low three bits and the top bit, set bit 254. *)
  let a = Z.(a land (shift_left one 254 - of_int 8) lor shift_left one 254) in
  a, String.drop_prefix h 32
;;

let public_key ~seed =
  let a, _ = expand seed in
  encode (mul a base)
;;

let sign ~seed msg =
  let a, prefix = expand seed in
  let pub = encode (mul a base) in
  let r = of_le (sha512 (prefix ^ msg)) %% l in
  let r_enc = encode (mul r base) in
  let k = of_le (sha512 (r_enc ^ pub ^ msg)) %% l in
  let s = Z.((r + (k * a)) %% l) in
  r_enc ^ to_le s ~len:32
;;

let verify ~public_key ~signature msg =
  String.length signature = 64
  &&
  match decode public_key, decode (String.prefix signature 32) with
  | Some a, Some r ->
    let s = of_le (String.drop_prefix signature 32) in
    Z.lt s l
    &&
    let k = of_le (sha512 (String.prefix signature 32 ^ public_key ^ msg)) %% l in
    equal_point (mul s base) (add r (mul k a))
  | _ -> false
;;
