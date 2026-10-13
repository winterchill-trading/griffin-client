(** Hypermedia links. Every Griffin resource names its related resources in fields ending
    in [-url] ([organization-bank-accounts-url], [account-payments-url], ...). This client
    navigates by those relations instead of building paths. *)

open! Core

(** Relation name (the field name, e.g. ["organization-url"]) to link. *)
type t [@@deriving sexp_of]

(** Every top-level string field of [json] whose name ends in [-url]. *)
val of_json : Yojson.Safe.t -> t

val find : t -> string -> string option

(** [find] or an error naming the missing relation and the ones present. *)
val find_or_error : t -> string -> string Or_error.t

val to_alist : t -> (string * string) list

(** Union; on a clash the left side wins. *)
val merge : t -> t -> t
