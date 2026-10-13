open! Core
open! Async

module Keys = struct
  type t = P521.Public_key.t String.Map.t [@@deriving sexp_of]

  let empty = String.Map.empty

  let of_jwks json =
    match Yojson.Safe.Util.member "keys" json with
    | `List keys ->
      Ok
        (List.filter_map keys ~f:(fun k ->
           match P521.Public_key.of_jwk k with
           | Ok (kid, key) -> Some (kid, key)
           | Error _ -> None)
         |> String.Map.of_alist_reduce ~f:(fun a _ -> a))
    | _ -> Or_error.error_string "JWKS has no keys array"
    | exception _ -> Or_error.error_string "JWKS is not an object"
  ;;

  let kids = Map.keys
  let find = Map.find

  let fetch transport =
    Transport.json transport `GET "/v0/security/public-keys" ()
    >>| Or_error.bind ~f:of_jwks
  ;;
end

let message ~meth ~authority ~path ?query ~headers ~body () =
  { Http_signature.Message.meth = String.uppercase meth
  ; authority = String.lowercase authority
  ; path
  ; query
  ; headers
  ; body
  }
;;

let check keys ~keyid ~base ~signature =
  match Keys.find keys keyid with
  | None -> Or_error.error_s [%message "unknown webhook signing key" keyid]
  | Some key -> Ok (P521.verify key ~signature base)
;;

let decode_event body =
  match Yojson.Safe.from_string body with
  | json -> Page.decode Model.Event.t_of_yojson json
  | exception _ -> Or_error.error_string "webhook body is not JSON"
;;

let verify ?now keys ~meth ~authority ~path ?query ~headers ~body () =
  let open Or_error.Let_syntax in
  let m = message ~meth ~authority ~path ?query ~headers ~body () in
  let%bind (_ : Http_signature.Input.t) =
    Http_signature.verify ?now m ~check:(check keys)
  in
  decode_event body
;;

let unknown_keyid keys headers =
  List.find_map headers ~f:(fun (k, v) ->
    if String.Caseless.equal k "signature-input" then Some v else None)
  |> Option.bind ~f:(fun v -> Http_signature.Input.parse v |> Result.ok)
  |> Option.value ~default:[]
  |> List.exists ~f:(fun (i : Http_signature.Input.t) ->
    match i.keyid with
    | Some kid -> Option.is_none (Keys.find keys kid)
    | None -> false)
;;

let verify_refreshing ?now transport keys ~meth ~authority ~path ?query ~headers ~body () =
  let open Deferred.Or_error.Let_syntax in
  let%bind keys =
    if unknown_keyid keys headers then Keys.fetch transport else return keys
  in
  let%map event =
    Deferred.return (verify ?now keys ~meth ~authority ~path ?query ~headers ~body ())
  in
  event, keys
;;
