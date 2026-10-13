open! Core
open! Async

let path = "/v0/index"

let fetch transport =
  Transport.json transport `GET path () |> Deferred.Or_error.map ~f:Links.of_json
;;
