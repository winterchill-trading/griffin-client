(** Verify webhook deliveries from Griffin.

    Griffin signs each delivery with RFC 9421 message signatures over
    [date @method @path @authority content-type content-length content-digest], using
    ES512 keys published at [GET /v0/security/public-keys]. Keys never change once
    published; cache them and refetch only for an unknown [keyid]. *)

open! Core
open! Async

module Keys : sig
  type t [@@deriving sexp_of]

  val empty : t

  (** Parse a JWKS document ([{"keys": [...]}]); non-P-521 keys are skipped. *)
  val of_jwks : Yojson.Safe.t -> t Or_error.t

  val kids : t -> string list
  val find : t -> string -> P521.Public_key.t option

  (** [GET /v0/security/public-keys] (no API key needed, but sent anyway). *)
  val fetch : Transport.t -> t Or_error.t Deferred.t
end

(** Check a delivery received by your HTTPS endpoint. [authority] is the host (and port)
    the delivery was addressed to, [path] and [query] its request target. [now], when
    given, rejects expired signatures. Returns the decoded event. *)
val verify
  :  ?now:Time_ns.t
  -> Keys.t
  -> meth:string
  -> authority:string
  -> path:string
  -> ?query:string
  -> headers:(string * string) list
  -> body:string
  -> unit
  -> Model.Event.t Or_error.t

(** Like [verify], but refetches the keys once when the [keyid] is unknown and returns the
    (possibly refreshed) key set to cache. *)
val verify_refreshing
  :  ?now:Time_ns.t
  -> Transport.t
  -> Keys.t
  -> meth:string
  -> authority:string
  -> path:string
  -> ?query:string
  -> headers:(string * string) list
  -> body:string
  -> unit
  -> (Model.Event.t * Keys.t) Or_error.t Deferred.t
