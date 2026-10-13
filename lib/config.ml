open! Core

module Signing = struct
  type t =
    { key_id : string
    ; private_key : Secret.t
    }
  [@@deriving sexp_of]
end

module Url = struct
  type t = Uri.t

  let sexp_of_t u = Sexp.Atom (Uri.to_string u)
end

type t =
  { base_url : Url.t
  ; api_key : Secret.t
  ; signing : Signing.t option
  ; live : bool
  }
[@@deriving sexp_of]

let default_base_url = Uri.of_string "https://api.griffin.com"

let create ?(base_url = default_base_url) ?signing ?(live = false) ~api_key () =
  let api_key = String.strip api_key in
  if String.is_empty api_key
  then Or_error.error_string "GRIFFIN_API_KEY is empty"
  else if (not live) && not (String.is_prefix api_key ~prefix:"g-test-")
  then
    (* Sandbox keys are documented as [g-test-...]. Anything else may reach a live
       organization, which needs an explicit opt-in. *)
    Or_error.error_string
      "API key is not a sandbox (g-test-) key; pass ~live:true to use it"
  else Ok { base_url; api_key = Secret.of_string api_key; signing; live }
;;

(* PKCS#8 wrapping of an Ed25519 private key, as written by
   [openssl genpkey -algorithm ed25519]: this 16-byte prefix and the 32-byte seed. *)
let pkcs8_ed25519_prefix =
  "\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20"
;;

let decode_base64 s =
  match Base64.decode ~pad:false s with
  | Ok v -> Some v
  | Error _ -> None
;;

let decode_hex s =
  if String.length s % 2 <> 0 || not (String.for_all s ~f:Char.is_hex_digit)
  then None
  else Some (Cryptokit.transform_string (Cryptokit.Hexa.decode ()) s)
;;

let parse_ed25519_private_key text =
  let text = String.strip text in
  if String.is_prefix text ~prefix:"-----BEGIN"
  then (
    let body =
      String.split_lines text
      |> List.filter ~f:(fun l -> not (String.is_prefix l ~prefix:"-----"))
      |> String.concat
      |> String.filter ~f:(fun c -> not (Char.is_whitespace c))
    in
    match decode_base64 body with
    | Some der
      when String.length der = 48 && String.is_prefix der ~prefix:pkcs8_ed25519_prefix ->
      Ok (String.drop_prefix der 16)
    | Some _ -> Or_error.error_string "PEM is not a PKCS#8 Ed25519 private key"
    | None -> Or_error.error_string "PEM body is not valid base64")
  else (
    let candidates =
      [ (if String.length text = 64 then decode_hex text else None); decode_base64 text ]
    in
    match List.find_map candidates ~f:Fn.id with
    | Some seed when String.length seed = 32 -> Ok seed
    | Some der
      when String.length der = 48 && String.is_prefix der ~prefix:pkcs8_ed25519_prefix ->
      Ok (String.drop_prefix der 16)
    | _ ->
      Or_error.error_string
        "signing key must be a PKCS#8 PEM or a 32-byte seed in base64 or hex")
;;

let non_empty getenv name =
  match getenv name with
  | Some v when not (String.is_empty (String.strip v)) -> Some (String.strip v)
  | _ -> None
;;

let env_available ?(getenv = Sys.getenv) () =
  Option.is_some (non_empty getenv "GRIFFIN_API_KEY")
;;

let of_env ?(getenv = Sys.getenv) ?live () =
  let open Or_error.Let_syntax in
  let%bind api_key =
    match non_empty getenv "GRIFFIN_API_KEY" with
    | Some k -> Ok k
    | None -> Or_error.error_string "GRIFFIN_API_KEY is not set"
  in
  let%bind base_url =
    match non_empty getenv "GRIFFIN_API_BASE_URL" with
    | None -> Ok default_base_url
    | Some s ->
      let uri = Uri.of_string s in
      (match Uri.scheme uri, Uri.host uri with
       | Some ("https" | "http"), Some _ -> Ok uri
       | _ -> Or_error.error_s [%message "GRIFFIN_API_BASE_URL is not an http(s) URL"])
  in
  let%bind signing =
    match
      non_empty getenv "GRIFFIN_SIGNING_KEY", non_empty getenv "GRIFFIN_SIGNING_KEY_ID"
    with
    | None, None -> Ok None
    | Some key, Some key_id ->
      let%map seed =
        Or_error.tag (parse_ed25519_private_key key) ~tag:"GRIFFIN_SIGNING_KEY"
      in
      Some { Signing.key_id; private_key = Secret.of_string seed }
    | Some _, None | None, Some _ ->
      Or_error.error_string
        "set both GRIFFIN_SIGNING_KEY and GRIFFIN_SIGNING_KEY_ID, or neither"
  in
  create ~base_url ?signing ?live ~api_key ()
;;
