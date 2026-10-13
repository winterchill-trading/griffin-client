open! Core
open! Async

(* Certificate checks against badssl.com. The network may be absent (sandboxed builds), so
   a host that does not resolve skips the check instead of failing. *)

let get ?ssl_config url =
  match%map
    Clock_ns.with_timeout
      (Time_ns.Span.of_sec 20.)
      (Monitor.try_with ~extract_exn:true (fun () ->
         let%bind _resp, body = Cohttp_async.Client.get ?ssl_config (Uri.of_string url) in
         let%map (_ : string) = Cohttp_async.Body.to_string body in
         ()))
  with
  | `Timeout -> `Timeout
  | `Result (Ok ()) -> `Ok
  | `Result (Error _) -> `Rejected
;;

let resolves host =
  match%map
    Monitor.try_with (fun () ->
      Clock_ns.with_timeout
        (Time_ns.Span.of_sec 5.)
        (Async_unix.Unix.Inet_addr.of_string_or_getbyname host))
  with
  | Ok (`Result _) -> true
  | _ -> false
;;

let show = function
  | `Ok -> "accepted"
  | `Rejected -> "rejected"
  | `Timeout -> "timeout"
;;

(* Measured 2026-10-13 with conduit-async 8.0.0: cohttp's default config rejects
   self-signed, expired and untrusted-root certificates but ACCEPTS wrong.host (no
   host-name check). [Tls.config] must reject all four and still accept a good one. Prints
   nothing, so the result is the same online and offline; a timeout skips. *)
let%expect_test "Tls.config rejects bad certificates" =
  let%bind online = resolves "badssl.com" in
  if not online
  then return ()
  else
    Deferred.List.iter
      ~how:`Sequential
      [ "self-signed", `Rejected
      ; "expired", `Rejected
      ; "wrong.host", `Rejected
      ; "untrusted-root", `Rejected
      ; "sha256", `Ok
      ]
      ~f:(fun (sub, expected) ->
        let host = sub ^ ".badssl.com" in
        match%map
          get ~ssl_config:(Griffin_client.Tls.config ~host) ("https://" ^ host ^ "/")
        with
        | `Timeout -> ()
        | got ->
          if not (String.equal (show got) (show expected))
          then
            raise_s
              [%message
                "unexpected TLS outcome" host ~got:(show got) ~expected:(show expected)])
;;
