open! Core

type 'a t =
  { items : 'a list
  ; next : string option
  ; prev : string option
  ; total : int option
  }
[@@deriving sexp_of]

let decode f json =
  match f json with
  | v -> Ok v
  | exception Ppx_yojson_conv_lib.Yojson_conv.Of_yojson_error (exn, bad) ->
    let what =
      match exn with
      | Failure msg ->
        (* Drop the "path/to/model.ml.Foo.t_of_yojson: " prefix. *)
        (match String.rsplit2 msg ~on:':' with
         | Some (_, rest) -> String.strip rest
         | None -> msg)
      | exn -> Exn.to_string exn
    in
    Or_error.error_s
      [%message "unexpected JSON" what ~near:(Yojson.Safe.to_string bad |> fun s -> String.prefix s 200 : string)]
  | exception Yojson.Safe.Util.Type_error (msg, _) -> Or_error.error_s [%message "unexpected JSON" msg]
;;

let of_json ~key f json =
  let open Or_error.Let_syntax in
  let open Yojson.Safe.Util in
  let%bind items =
    match member key json with
    | `List l -> List.map l ~f:(decode f) |> Or_error.all
    | `Null -> Ok []
    | _ -> Or_error.error_s [%message "list field is not an array" key]
  in
  let link name =
    match member "links" json with
    | `Assoc _ as links ->
      (match member name links with
       | `String s -> Some s
       | _ -> None)
    | _ -> None
  in
  let total =
    match member "meta" json with
    | `Assoc _ as meta ->
      (match member "page" meta with
       | `Assoc _ as page ->
         (match member "total" page with
          | `Int n -> Some n
          | _ -> None)
       | _ -> None)
    | _ -> None
  in
  return { items; next = link "next"; prev = link "prev"; total }
;;
