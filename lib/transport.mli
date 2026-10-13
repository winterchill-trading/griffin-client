(** HTTP transport: API key header, optional RFC 9421 signing, retries with backoff, a cap
    on in-flight requests, client request ids and redaction.

    Every status comes back as [Ok] from {!call}; the JSON helpers turn non-2xx into an
    [Error] carrying an {!Api_error.t}. *)

open! Core
open! Async

module Meth : sig
  type t =
    [ `GET
    | `POST
    | `PUT
    | `PATCH
    | `DELETE
    ]
  [@@deriving sexp_of, equal]

  val to_string : t -> string
end

module Response : sig
  type t =
    { status : int
    ; headers : (string * string) list
    ; body : string
    }
  [@@deriving sexp_of]

  val header : t -> string -> string option
end

(** One HTTP exchange; the default is cohttp-async with {!Tls.config}. *)
type send =
  meth:Meth.t
  -> Uri.t
  -> headers:(string * string) list
  -> body:string option
  -> Response.t Or_error.t Deferred.t

(** What happened on one attempt, for logging. Holds no headers or bodies. *)
module Event : sig
  type t =
    { request_id : string
    ; meth : Meth.t
    ; path : string
    ; attempt : int
    ; outcome : [ `Status of int | `Failed of string ]
    ; elapsed : Time_ns.Span.t
    }
  [@@deriving sexp_of]
end

type t

val create
  :  ?send:send
  -> ?sleep:(Time_ns.Span.t -> unit Deferred.t)
  -> ?now:(unit -> Time_ns.t)
  -> ?max_retries:int (** default 4 *)
  -> ?max_in_flight:int (** default 16; Griffin allows 50 per organization *)
  -> ?timeout:Time_ns.Span.t (** per attempt, default 30 s *)
  -> ?on_event:(Event.t -> unit)
  -> Config.t
  -> t

val config : t -> Config.t

(** Turn a link from a response ([/v0/...]) or a full URL on the configured host into a
    URI. Refuses URLs on other hosts so the API key never leaves for them. *)
val resolve : t -> string -> Uri.t Or_error.t

(** Backoff before retry [attempt] (1-based): 250 ms doubling up to 8 s, or the response's
    [Retry-After] seconds when present. *)
val backoff : attempt:int -> retry_after:string option -> Time_ns.Span.t

(** One logical request; returns the response and the client request id. Retries 429/5xx
    and transport failures when the request is idempotent: GET, PUT and DELETE always,
    other methods only with [~idempotent:true] (payment submissions). *)
val call
  :  ?idempotent:bool
  -> t
  -> Meth.t
  -> string
  -> ?body:Yojson.Safe.t
  -> unit
  -> (Response.t * string) Or_error.t Deferred.t

(** [call], then decode a 2xx JSON body; non-2xx becomes {!Api_error.to_error}. *)
val json
  :  ?idempotent:bool
  -> t
  -> Meth.t
  -> string
  -> ?body:Yojson.Safe.t
  -> unit
  -> Yojson.Safe.t Or_error.t Deferred.t

(** Like {!json} for endpoints answering 204 or an empty body. *)
val unit
  :  ?idempotent:bool
  -> t
  -> Meth.t
  -> string
  -> ?body:Yojson.Safe.t
  -> unit
  -> unit Or_error.t Deferred.t

(** The default [send], exposed for tests and tools. *)
val cohttp_send : timeout:Time_ns.Span.t -> send
