open! Core

module Message = struct
  type t =
    { meth : string
    ; authority : string
    ; path : string
    ; query : string option
    ; headers : (string * string) list
    ; body : string
    }
  [@@deriving sexp_of]

  let of_uri ~meth uri ~headers ~body =
    let host = Option.value (Uri.host uri) ~default:"" |> String.lowercase in
    let authority =
      match Uri.port uri, Uri.scheme uri with
      | None, _ | Some 443, Some "https" | Some 80, Some "http" -> host
      | Some port, _ -> sprintf "%s:%d" host port
    in
    let path =
      match Uri.path uri with
      | "" -> "/"
      | p -> p
    in
    let query = Uri.verbatim_query uri in
    { meth = String.uppercase meth; authority; path; query; headers; body }
  ;;

  let header t name =
    List.find_map t.headers ~f:(fun (k, v) ->
      if String.Caseless.equal k name then Some (String.strip v) else None)
  ;;
end

let sha512 s = Cryptokit.hash_string (Cryptokit.Hash.sha512 ()) s
let content_digest body = sprintf "sha-512=:%s:" (Base64.encode_exn (sha512 body))

let http_date time =
  let date, ofday = Time_ns.to_date_ofday time ~zone:Time_float.Zone.utc in
  let parts = Time_ns.Ofday.to_parts ofday in
  sprintf
    "%s, %02d %s %d %02d:%02d:%02d GMT"
    (Day_of_week.to_string (Date.day_of_week date)
     |> String.lowercase
     |> String.capitalize)
    (Date.day date)
    (Month.to_string (Date.month date) |> String.lowercase |> String.capitalize)
    (Date.year date)
    parts.hr
    parts.min
    parts.sec
;;

let uuid_v4 () =
  let b = Bytes.of_string (Cryptokit.Random.string Cryptokit.Random.secure_rng 16) in
  let set i f = Bytes.set b i (Char.of_int_exn (f (Char.to_int (Bytes.get b i)))) in
  set 6 (fun c -> c land 0x0f lor 0x40);
  set 8 (fun c -> c land 0x3f lor 0x80);
  let h = Cryptokit.transform_string (Cryptokit.Hexa.encode ()) (Bytes.to_string b) in
  sprintf
    "%s-%s-%s-%s-%s"
    (String.sub h ~pos:0 ~len:8)
    (String.sub h ~pos:8 ~len:4)
    (String.sub h ~pos:12 ~len:4)
    (String.sub h ~pos:16 ~len:4)
    (String.sub h ~pos:20 ~len:12)
;;

let default_components =
  [ "@authority"
  ; "content-digest"
  ; "content-length"
  ; "content-type"
  ; "date"
  ; "@method"
  ; "@path"
  ; "@query"
  ]
;;

let component_value (m : Message.t) name =
  match name with
  | "@method" -> Ok m.meth
  | "@authority" -> Ok m.authority
  | "@path" -> Ok m.path
  | "@query" -> Ok ("?" ^ Option.value m.query ~default:"")
  | "@target-uri" | "@request-target" | "@scheme" ->
    Or_error.error_s [%message "unsupported derived component" name]
  | _ ->
    (match Message.header m name with
     | Some v -> Ok v
     | None when String.equal name "content-digest" -> Ok ""
     | None -> Or_error.error_s [%message "header missing for signature component" name])
;;

let signature_base m ~components ~params =
  let open Or_error.Let_syntax in
  let%map lines =
    List.map components ~f:(fun c ->
      let%map v = component_value m c in
      sprintf "%S: %s" c v)
    |> Or_error.all
  in
  String.concat ~sep:"\n" (lines @ [ "\"@signature-params\": " ^ params ])
;;

let sign
  ?(label = "sig1")
  ?(components = default_components)
  m
  ~key_id
  ~seed
  ~created
  ~nonce
  =
  let open Or_error.Let_syntax in
  let digest = content_digest m.Message.body in
  let m =
    { m with
      headers =
        ("content-digest", digest)
        :: List.filter m.headers ~f:(fun (k, _) ->
          not (String.Caseless.equal k "content-digest"))
    }
  in
  let created = Time_ns.to_int_ns_since_epoch created / 1_000_000_000 in
  let params =
    sprintf
      "(%s);alg=\"ed25519\";created=%d;expires=%d;keyid=%S;nonce=%S"
      (String.concat ~sep:" " (List.map components ~f:(sprintf "%S")))
      created
      (created + 300)
      key_id
      nonce
  in
  let%map base = signature_base m ~components ~params in
  let signature = Ed25519.sign ~seed base in
  [ "content-digest", digest
  ; "signature-input", sprintf "%s=%s" label params
  ; "signature", sprintf "%s=:%s:" label (Base64.encode_exn signature)
  ]
;;

module Input = struct
  type t =
    { label : string
    ; components : string list
    ; params : string
    ; created : int option
    ; expires : int option
    ; keyid : string option
    ; nonce : string option
    ; alg : string option
    }
  [@@deriving sexp_of]

  exception Bad of string

  let parse s =
    let len = String.length s in
    let pos = ref 0 in
    let peek () = if !pos < len then Some s.[!pos] else None in
    let bad what = raise (Bad what) in
    let skip_ws () =
      while
        match peek () with
        | Some (' ' | '\t') -> true
        | _ -> false
      do
        incr pos
      done
    in
    let expect c =
      if Option.equal Char.equal (peek ()) (Some c)
      then incr pos
      else bad (sprintf "expected %c" c)
    in
    let token () =
      let start = !pos in
      while
        match peek () with
        | Some c -> Char.is_alphanum c || String.mem "_-.*:/%" c
        | None -> false
      do
        incr pos
      done;
      if !pos = start then bad "expected a token";
      String.sub s ~pos:start ~len:(!pos - start)
    in
    let quoted () =
      expect '"';
      let buf = Buffer.create 16 in
      let rec loop () =
        match peek () with
        | None -> bad "unterminated string"
        | Some '"' -> incr pos
        | Some '\\' ->
          incr pos;
          (match peek () with
           | Some c ->
             Buffer.add_char buf c;
             incr pos;
             loop ()
           | None -> bad "bad escape")
        | Some c ->
          Buffer.add_char buf c;
          incr pos;
          loop ()
      in
      loop ();
      Buffer.contents buf
    in
    let one () =
      skip_ws ();
      let label = token () in
      expect '=';
      let params_start = !pos in
      expect '(';
      let rec comps acc =
        skip_ws ();
        match peek () with
        | Some ')' ->
          incr pos;
          List.rev acc
        | Some '"' -> comps (quoted () :: acc)
        | _ -> bad "expected a component name"
      in
      let components = comps [] in
      let rec params acc =
        match peek () with
        | Some ';' ->
          incr pos;
          let key = token () in
          expect '=';
          let value =
            match peek () with
            | Some '"' -> quoted ()
            | _ -> token ()
          in
          params ((key, value) :: acc)
        | _ -> List.rev acc
      in
      let kv = params [] in
      let params = String.sub s ~pos:params_start ~len:(!pos - params_start) in
      let find k = List.Assoc.find kv k ~equal:String.equal in
      let int k = Option.bind (find k) ~f:Int.of_string_opt in
      { label
      ; components
      ; params
      ; created = int "created"
      ; expires = int "expires"
      ; keyid = find "keyid"
      ; nonce = find "nonce"
      ; alg = find "alg"
      }
    in
    let rec all acc =
      let t = one () in
      skip_ws ();
      match peek () with
      | Some ',' ->
        incr pos;
        all (t :: acc)
      | None -> List.rev (t :: acc)
      | Some _ -> bad "trailing characters"
    in
    try Ok (all []) with
    | Bad what -> Or_error.error_s [%message "malformed signature-input" what]
  ;;
end

let parse_signatures s =
  String.split s ~on:','
  |> List.map ~f:String.strip
  |> List.filter ~f:(Fn.non String.is_empty)
  |> List.map ~f:(fun item ->
    match String.lsplit2 item ~on:'=' with
    | Some (label, v)
      when String.length v >= 2
           && String.is_prefix v ~prefix:":"
           && String.is_suffix v ~suffix:":" ->
      (match Base64.decode (String.sub v ~pos:1 ~len:(String.length v - 2)) with
       | Ok raw -> Ok (String.strip label, raw)
       | Error _ -> Or_error.error_s [%message "signature is not base64" label])
    | _ -> Or_error.error_s [%message "malformed signature header"])
  |> Or_error.all
;;

let verify ?now (m : Message.t) ~check =
  let open Or_error.Let_syntax in
  let%bind input_header =
    Result.of_option
      (Message.header m "signature-input")
      ~error:(Error.of_string "signature-input header missing")
  in
  let%bind sig_header =
    Result.of_option
      (Message.header m "signature")
      ~error:(Error.of_string "signature header missing")
  in
  let%bind inputs = Input.parse input_header in
  let%bind sigs = parse_signatures sig_header in
  let%bind () =
    match Message.header m "content-digest" with
    | None -> Or_error.error_string "content-digest header missing"
    | Some d ->
      if String.equal d (content_digest m.body)
      then Ok ()
      else Or_error.error_string "content-digest does not match the body"
  in
  let try_one (input : Input.t) =
    let%bind keyid =
      Result.of_option input.keyid ~error:(Error.of_string "signature has no keyid")
    in
    let%bind signature =
      Result.of_option
        (List.Assoc.find sigs input.label ~equal:String.equal)
        ~error:(Error.create_s [%message "no signature for label" input.label])
    in
    let%bind () =
      match now, input.expires with
      | Some now, Some expires
        when Time_ns.to_int_ns_since_epoch now / 1_000_000_000 > expires ->
        Or_error.error_s [%message "signature expired" (expires : int)]
      | _ -> Ok ()
    in
    let%bind () =
      if List.mem input.components "content-digest" ~equal:String.equal
      then Ok ()
      else Or_error.error_string "signature does not cover content-digest"
    in
    let%bind base = signature_base m ~components:input.components ~params:input.params in
    match%bind check ~keyid ~base ~signature with
    | true -> Ok input
    | false -> Or_error.error_s [%message "signature does not verify" keyid]
  in
  match inputs with
  | [] -> Or_error.error_string "no signatures"
  | inputs ->
    List.map inputs ~f:try_one
    |> List.reduce_exn ~f:(fun a b ->
      match a with
      | Ok _ -> a
      | Error _ -> b)
;;
