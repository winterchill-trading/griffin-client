(** A non-2xx response from Griffin. Error bodies look like
    [{"errors":[{"title":..., "status":"404", "detail":..., "code":...}]}]; [detail] is
    sometimes a list (missing signature components), kept here as compact JSON. *)

open! Core

module Problem : sig
  type t =
    { title : string option
    ; status : string option
    ; detail : string option
    ; code : string option
    }
  [@@deriving sexp_of]
end

type t =
  { meth : string
  ; path : string
  ; status : int
  ; request_id : string (** client-generated, sent as [x-request-id] *)
  ; problems : Problem.t list
  ; body : string (** redacted and cut to 2 KiB, only when [problems] is empty *)
  }
[@@deriving sexp_of]

val of_response
  :  meth:string
  -> path:string
  -> request_id:string
  -> redact:(string -> string)
  -> status:int
  -> body:string
  -> t

(** The first problem's [code], e.g. ["unknown-signing-key-id"]. *)
val code : t -> string option

val to_error : t -> Error.t

(** Recover the HTTP status from an error built by {!to_error}, also through
    [Or_error.tag]. *)
val status_of_error : Error.t -> int option
