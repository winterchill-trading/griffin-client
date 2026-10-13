(** ECDSA over NIST P-521 with SHA-512 (JOSE [ES512]), the algorithm Griffin uses to sign
    webhook deliveries. Verification only for real use; [For_testing.sign] exists so tests
    can produce webhooks. Checked against OpenSSL in the tests. *)

open! Core

module Public_key : sig
  type t [@@deriving sexp_of]

  (** Big-endian affine coordinates (any length up to 66 bytes). Fails when the point is
      not on the curve. *)
  val of_coordinates : x:string -> y:string -> t Or_error.t

  (** A JSON Web Key with [kty = "EC"] and [crv = "P-521"]; returns its [kid]. *)
  val of_jwk : Yojson.Safe.t -> (string * t) Or_error.t
end

(** [verify key ~signature msg] hashes [msg] with SHA-512. [signature] is either DER
    ([SEQUENCE { INTEGER r, INTEGER s }], as Griffin sends) or raw [r || s] of 132 bytes
    (JOSE). *)
val verify : Public_key.t -> signature:string -> string -> bool

module For_testing : sig
  (** Public key of private scalar [d] (big-endian bytes). *)
  val public_key : d:string -> Public_key.t

  (** DER signature with private scalar [d] and nonce [k] (big-endian bytes). Never reuse
      [k]; this is for building test webhooks only. *)
  val sign : d:string -> k:string -> string -> string
end
