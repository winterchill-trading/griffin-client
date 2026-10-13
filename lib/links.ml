open! Core

type t = string String.Map.t [@@deriving sexp_of]

let of_json = function
  | `Assoc kv ->
    List.filter_map kv ~f:(fun (k, v) ->
      match v with
      | `String s when String.is_suffix k ~suffix:"-url" -> Some (k, s)
      | _ -> None)
    |> String.Map.of_alist_reduce ~f:(fun a _ -> a)
  | _ -> String.Map.empty
;;

let find t rel = Map.find t rel

let find_or_error t rel =
  match Map.find t rel with
  | Some v -> Ok v
  | None ->
    Or_error.error_s
      [%message "link relation not found" rel ~available:(Map.keys t : string list)]
;;

let to_alist t = Map.to_alist t
let merge a b = Map.merge_skewed a b ~combine:(fun ~key:_ l _ -> l)
