(** Client configuration, read from environment variables.

    - [GRIFFIN_API_KEY] (required): the API key. Sandbox keys start with [g-test-].
    - [GRIFFIN_API_BASE_URL] (optional, default [https://api.griffin.com]).
    - [GRIFFIN_SIGNING_KEY] and [GRIFFIN_SIGNING_KEY_ID] (optional, both or neither): an
      Ed25519 private key (PEM, or the 32-byte seed in base64 or hex) and the key id the
      Griffin app assigned to its public key. When set, every request is signed with RFC
      9421 message signatures.

    The library defaults to the sandbox: a key that is not a [g-test-] key is refused
    unless [~live:true] is passed. *)

open! Core

module Signing : sig
  type t =
    { key_id : string
    ; private_key : Secret.t (** the 32-byte Ed25519 seed *)
    }
  [@@deriving sexp_of]
end

type t =
  { base_url : Uri.t
  ; api_key : Secret.t
  ; signing : Signing.t option
  ; live : bool
  }

val sexp_of_t : t -> Sexp.t
val default_base_url : Uri.t

val create
  :  ?base_url:Uri.t
  -> ?signing:Signing.t
  -> ?live:bool
  -> api_key:string
  -> unit
  -> t Or_error.t

(** [of_env ()] reads the variables above; [getenv] defaults to [Sys.getenv]. *)
val of_env : ?getenv:(string -> string option) -> ?live:bool -> unit -> t Or_error.t

(** [true] when [GRIFFIN_API_KEY] is set and non-empty. Live tests use it to skip. *)
val env_available : ?getenv:(string -> string option) -> unit -> bool

(** Parse an Ed25519 private key: PKCS#8 PEM ([openssl genpkey -algorithm ed25519]), or
    the raw 32-byte seed as base64 or hex. Returns the seed. *)
val parse_ed25519_private_key : string -> string Or_error.t
