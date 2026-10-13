(** The API entry point, [GET /v0/index]: links to the caller's organization, API key,
    users and roles. *)

open! Core
open! Async

val path : string
val fetch : Transport.t -> Links.t Or_error.t Deferred.t
