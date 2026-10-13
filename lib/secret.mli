(** A string that never prints. Its sexp and [to_string_hum] show [<redacted>], so a
    secret can sit inside records that derive [sexp_of] without leaking into logs. *)

open! Core

type t [@@deriving sexp_of]

val of_string : string -> t

(** The raw value, for building a header. Do not log the result. *)
val reveal : t -> string

(** Replace every occurrence of the secret in [text] with [<redacted>]. *)
val redact : t -> string -> string
