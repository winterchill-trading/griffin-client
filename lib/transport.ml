open! Core
open! Async

module Meth = struct
  type t =
    [ `GET
    | `POST
    | `PUT
    | `PATCH
    | `DELETE
    ]
  [@@deriving sexp_of, equal]

  let to_string = function
    | `GET -> "GET"
    | `POST -> "POST"
    | `PUT -> "PUT"
    | `PATCH -> "PATCH"
    | `DELETE -> "DELETE"
  ;;
end

module Response = struct
  type t =
    { status : int
    ; headers : (string * string) list
    ; body : string
    }
  [@@deriving sexp_of]

  let header t name =
    List.find_map t.headers ~f:(fun (k, v) ->
      if String.Caseless.equal k name then Some v else None)
  ;;
end

type send =
  meth:Meth.t
  -> Uri.t
  -> headers:(string * string) list
  -> body:string option
  -> Response.t Or_error.t Deferred.t

module Event = struct
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

type t =
  { config : Config.t
  ; send : send
  ; sleep : Time_ns.Span.t -> unit Deferred.t
  ; now : unit -> Time_ns.t
  ; max_retries : int
  ; throttle : unit Throttle.t
  ; on_event : Event.t -> unit
  }

let config t = t.config

let cohttp_send ~timeout ~meth uri ~headers ~body =
  let ssl_config =
    match Uri.scheme uri, Uri.host uri with
    | Some "https", Some host -> Some (Tls.config ~host)
    | _ -> None
  in
  let attempt () =
    let%bind resp, body =
      Cohttp_async.Client.call
        ?ssl_config
        ~headers:(Cohttp.Header.of_list headers)
        ?body:(Option.map body ~f:Cohttp_async.Body.of_string)
        (meth :> Cohttp.Code.meth)
        uri
    in
    let%map body = Cohttp_async.Body.to_string body in
    { Response.status = Cohttp.Code.code_of_status (Cohttp.Response.status resp)
    ; headers = Cohttp.Header.to_list (Cohttp.Response.headers resp)
    ; body
    }
  in
  match%map
    Clock_ns.with_timeout timeout (Monitor.try_with_or_error ~extract_exn:true attempt)
  with
  | `Timeout -> Or_error.error_s [%message "request timed out" (timeout : Time_ns.Span.t)]
  | `Result r -> r
;;

let create
  ?send
  ?(sleep = Clock_ns.after)
  ?(now = Time_ns.now)
  ?(max_retries = 4)
  ?(max_in_flight = 16)
  ?(timeout = Time_ns.Span.of_sec 30.)
  ?(on_event = ignore)
  config
  =
  let send = Option.value send ~default:(cohttp_send ~timeout) in
  { config
  ; send
  ; sleep
  ; now
  ; max_retries
  ; throttle = Throttle.create ~continue_on_error:true ~max_concurrent_jobs:max_in_flight
  ; on_event
  }
;;

let resolve t link =
  let base = t.config.base_url in
  let uri = Uri.of_string link in
  match Uri.host uri with
  | None ->
    if String.is_prefix link ~prefix:"/"
    then (
      let path, query =
        match String.lsplit2 link ~on:'?' with
        | Some (p, q) -> p, Some q
        | None -> link, None
      in
      let base_path = String.chop_suffix_if_exists (Uri.path base) ~suffix:"/" in
      let u = Uri.with_path base (base_path ^ path) in
      (* Keep the query text exactly as Griffin wrote it ([page[after]=...]). *)
      Ok
        (match query with
         | None -> Uri.with_query u []
         | Some q -> Uri.of_string (Uri.to_string (Uri.with_query u []) ^ "?" ^ q)))
    else Or_error.error_s [%message "link must start with /" link]
  | Some host ->
    if Option.equal String.Caseless.equal (Some host) (Uri.host base)
    then Ok uri
    else Or_error.error_s [%message "refusing to send the API key to another host" host]
;;

let backoff ~attempt ~retry_after =
  match Option.bind retry_after ~f:(fun s -> Int.of_string_opt (String.strip s)) with
  | Some secs when secs >= 0 -> Time_ns.Span.of_int_sec (Int.min secs 60)
  | _ ->
    let ms = 250 * (1 lsl Int.min (attempt - 1) 5) in
    Time_ns.Span.of_int_ms (Int.min ms 8000)
;;

let retryable_status s = s = 429 || s = 500 || s = 502 || s = 503 || s = 504

let headers_for t ~(meth : Meth.t) ~uri ~body ~request_id =
  let base =
    [ "authorization", "GriffinAPIKey " ^ Secret.reveal t.config.api_key
    ; "accept", "application/json"
    ; "x-request-id", request_id
    ]
  in
  let body_headers =
    match body with
    | Some b ->
      [ "content-type", "application/json"
      ; "content-length", Int.to_string (String.length b)
      ]
    | None -> []
  in
  match t.config.signing with
  | None -> Ok (base @ body_headers)
  | Some { key_id; private_key } ->
    let created = t.now () in
    (* Griffin signs content-type and content-length on every request, so send them on
       bodyless requests too. *)
    let body_headers =
      match body with
      | Some _ -> body_headers
      | None -> [ "content-type", "application/json"; "content-length", "0" ]
    in
    let headers = base @ body_headers @ [ "date", Http_signature.http_date created ] in
    let message =
      Http_signature.Message.of_uri
        ~meth:(Meth.to_string meth)
        uri
        ~headers
        ~body:(Option.value body ~default:"")
    in
    let%map.Or_error extra =
      Http_signature.sign
        message
        ~key_id
        ~seed:(Secret.reveal private_key)
        ~created
        ~nonce:(Http_signature.uuid_v4 ())
    in
    headers @ extra
;;

let redact t s = Secret.redact t.config.api_key s

let call ?idempotent t (meth : Meth.t) link ?body () =
  let idempotent =
    match idempotent with
    | Some b -> b
    | None ->
      (match meth with
       | `GET | `PUT | `DELETE -> true
       | `POST | `PATCH -> false)
  in
  match resolve t link with
  | Error _ as e -> return e
  | Ok uri ->
    let request_id = Http_signature.uuid_v4 () in
    let body = Option.map body ~f:Yojson.Safe.to_string in
    let path = Uri.path uri in
    let rec attempt n =
      match headers_for t ~meth ~uri ~body ~request_id with
      | Error _ as e -> return e
      | Ok headers ->
        let started = t.now () in
        let%bind result =
          Throttle.enqueue t.throttle (fun () -> t.send ~meth uri ~headers ~body)
        in
        let elapsed = Time_ns.diff (t.now ()) started in
        let outcome =
          match result with
          | Ok r -> `Status r.status
          | Error e -> `Failed (redact t (Error.to_string_hum e))
        in
        t.on_event { request_id; meth; path; attempt = n; outcome; elapsed };
        let retry ~retry_after =
          let%bind () = t.sleep (backoff ~attempt:n ~retry_after) in
          attempt (n + 1)
        in
        (match result with
         | Ok r when retryable_status r.status && idempotent && n <= t.max_retries ->
           retry ~retry_after:(Response.header r "retry-after")
         | Ok r -> return (Ok (r, request_id))
         | Error _ when idempotent && n <= t.max_retries -> retry ~retry_after:None
         | Error e ->
           return
             (Error
                (Error.create_s
                   [%message
                     "griffin request failed"
                       ~meth:(Meth.to_string meth)
                       path
                       request_id
                       ~error:(redact t (Error.to_string_hum e))])))
    in
    attempt 1
;;

let check t meth link (r : Response.t) request_id =
  if r.status >= 200 && r.status < 300
  then Ok r
  else
    Error
      (Api_error.to_error
         (Api_error.of_response
            ~meth:(Meth.to_string meth)
            ~path:(Uri.path (Uri.of_string link))
            ~request_id
            ~redact:(redact t)
            ~status:r.status
            ~body:r.body))
;;

let json ?idempotent t meth link ?body () =
  let%map result = call ?idempotent t meth link ?body () in
  let open Or_error.Let_syntax in
  let%bind r, request_id = result in
  let%bind r = check t meth link r request_id in
  Or_error.try_with (fun () -> Yojson.Safe.from_string r.body)
  |> Or_error.tag_s ~tag:[%message "response is not JSON" ~path:(link : string)]
;;

let unit ?idempotent t meth link ?body () =
  let%map result = call ?idempotent t meth link ?body () in
  let open Or_error.Let_syntax in
  let%bind r, request_id = result in
  let%map (_ : Response.t) = check t meth link r request_id in
  ()
;;
