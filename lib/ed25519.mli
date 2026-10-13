(** Ed25519 signatures (RFC 8032), in OCaml over Zarith and Cryptokit's SHA-512.

    Griffin signs nothing with Ed25519 but requires it for client request signatures. No
    Ed25519 implementation builds on the OxCaml switch (digestif, needed by
    mirage-crypto-ec, fails to compile), so this one is checked against the RFC 8032 test
    vectors and against OpenSSL in the tests. It is not constant time; it signs a few
    requests per second, not secrets in a shared process. *)

open! Core

(** [public_key ~seed] is the 32-byte public key of a 32-byte private seed. *)
val public_key : seed:string -> string

(** [sign ~seed msg] is the 64-byte signature. *)
val sign : seed:string -> string -> string

val verify : public_key:string -> signature:string -> string -> bool
