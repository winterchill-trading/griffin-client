(** TLS settings for every HTTPS request this library makes.

    cohttp-async's default client config (conduit-async 8.0.0) sets only the SNI hostname:
    certificate chains are checked by async_ssl's default [Verify_peer] against OpenSSL's
    default CA paths, but the certificate's host name is never compared with the URL's
    host, and conduit's [verify] hook defaults to accepting everything. {!config} adds an
    explicit host-name check and an explicit CA bundle. *)

open! Core

(** The CA bundle: [SSL_CERT_FILE] if set, else the first existing of the usual system and
    Homebrew locations, else [None] (OpenSSL's built-in default paths). *)
val ca_file : unit -> string option

(** Client config for [host]: [Verify_peer], CA bundle from {!ca_file}, and a [verify]
    hook that requires a validated peer certificate whose names match [host]. *)
val config : host:string -> Conduit_async.V2.Ssl.Config.t
