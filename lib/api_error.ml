open! Core

module Problem = struct
  type t =
    { title : string option
    ; status : string option
    ; detail : string option
    ; code : string option
    }
  [@@deriving sexp_of]

  let of_json json =
    let str name =
      match Yojson.Safe.Util.member name json with
      | `String s -> Some s
      | `Null -> None
      | other -> Some (Yojson.Safe.to_string other)
    in
    { title = str "title"
    ; status = str "status"
    ; detail = str "detail"
    ; code = str "code"
    }
  ;;
end

type t =
  { meth : string
  ; path : string
  ; status : int
  ; request_id : string
  ; problems : Problem.t list
  ; body : string
  }
[@@deriving sexp_of]

let of_response ~meth ~path ~request_id ~redact ~status ~body =
  let problems =
    match Yojson.Safe.from_string body with
    | `Assoc _ as json ->
      (match Yojson.Safe.Util.member "errors" json with
       | `List l ->
         List.filter_map l ~f:(function
           | `Assoc _ as p -> Some (Problem.of_json p)
           | _ -> None)
       | _ -> [])
    | _ -> []
    | exception _ -> []
  in
  let body =
    if List.is_empty problems
    then (
      let b = redact body in
      if String.length b > 2048 then String.prefix b 2048 ^ "..." else b)
    else ""
  in
  { meth
  ; path
  ; status
  ; request_id
  ; problems =
      List.map problems ~f:(fun p -> { p with detail = Option.map p.detail ~f:redact })
  ; body
  }
;;

let code t = List.find_map t.problems ~f:(fun p -> p.code)
let tag = "griffin http error"
let to_error t = Error.create_s [%sexp (tag : string), (t : t)]

(* Search the whole sexp, so the status survives [Or_error.tag] wrappers. *)
let status_of_error e =
  let rec find = function
    | Sexp.Atom _ -> None
    | Sexp.List [ Atom tag'; List items ] when String.equal tag tag' ->
      List.find_map items ~f:(function
        | List [ Atom "status"; Atom s ] -> Int.of_string_opt s
        | _ -> None)
    | Sexp.List l -> List.find_map l ~f:find
  in
  find (Error.sexp_of_t e)
;;
