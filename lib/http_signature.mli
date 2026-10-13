(** HTTP message signatures (RFC 9421) as Griffin uses them, with SHA-512 content digests
    (RFC 9530).

    Requests to Griffin are signed with Ed25519 over the components
    [@authority content-digest content-length content-type date @method @path @query] and
    the parameters [alg created expires keyid nonce]. Webhook deliveries from Griffin
    carry the same headers, signed with ES512; {!verify} checks those against a
    caller-supplied signature check. *)

open! Core

module Message : sig
  (** What a signature covers. [headers] names are matched case-insensitively. *)
  type t =
    { meth : string
    ; authority : string (** host, plus [:port] when not the scheme default *)
    ; path : string
    ; query : string option (** without the leading [?] *)
    ; headers : (string * string) list
    ; body : string
    }
  [@@deriving sexp_of]

  val of_uri : meth:string -> Uri.t -> headers:(string * string) list -> body:string -> t
end

(** [sha-512=:<base64>:] *)
val content_digest : string -> string

(** IMF-fixdate, e.g. [Mon, 23 Sep 2024 08:52:47 GMT], for the [date] header. *)
val http_date : Time_ns.t -> string

(** A random UUID v4, used as the signature nonce and the client request id. *)
val uuid_v4 : unit -> string

val default_components : string list

(** The signature base (RFC 9421 section 2.5) for [components] and the serialized
    parameter string [params] (everything after the label in [signature-input]). Fails
    when a header component is missing from the message. A missing [content-digest] header
    signs as the empty string, which Griffin accepts for bodiless requests. *)
val signature_base
  :  Message.t
  -> components:string list
  -> params:string
  -> string Or_error.t

(** Headers to add to a request ([content-digest], [signature-input], [signature]). The
    message must already carry [date], [content-type] and [content-length]. The signature
    expires five minutes after [created], Griffin's maximum. *)
val sign
  :  ?label:string
  -> ?components:string list
  -> Message.t
  -> key_id:string
  -> seed:string
  -> created:Time_ns.t
  -> nonce:string
  -> (string * string) list Or_error.t

module Input : sig
  type t =
    { label : string
    ; components : string list
    ; params : string (** serialized, exactly as received *)
    ; created : int option
    ; expires : int option
    ; keyid : string option
    ; nonce : string option
    ; alg : string option
    }
  [@@deriving sexp_of]

  (** Parse a [signature-input] header value (one or more comma-separated labels). *)
  val parse : string -> t list Or_error.t
end

(** Parse a [signature] header value into [(label, raw signature bytes)]. *)
val parse_signatures : string -> (string * string) list Or_error.t

(** Verify the first signature whose [keyid] [check] accepts: the body must match
    [content-digest], [expires] must not be before [now], and
    [check ~keyid ~base ~signature] must return [true]. Returns the accepted input. *)
val verify
  :  ?now:Time_ns.t
  -> Message.t
  -> check:(keyid:string -> base:string -> signature:string -> bool Or_error.t)
  -> Input.t Or_error.t
