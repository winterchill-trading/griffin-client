(** One page of a list response: [{"<key>": [...], "links": {"prev", "next"},
    "meta": {"page": {"total"}}}]. [next] and [prev] are links to follow verbatim. *)

open! Core

type 'a t =
  { items : 'a list
  ; next : string option
  ; prev : string option
  ; total : int option
  }
[@@deriving sexp_of]

(** Decode a JSON value with a [t_of_yojson] function; decoder exceptions become an
    [Error] without source paths (they differ between build layouts). *)
val decode : (Yojson.Safe.t -> 'a) -> Yojson.Safe.t -> 'a Or_error.t

val of_json : key:string -> (Yojson.Safe.t -> 'a) -> Yojson.Safe.t -> 'a t Or_error.t
