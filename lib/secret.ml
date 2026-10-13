open! Core

type t = string

let sexp_of_t (_ : t) = Sexp.Atom "<redacted>"
let of_string s = s
let reveal t = t

let redact t text =
  if String.is_empty t
  then text
  else String.substr_replace_all text ~pattern:t ~with_:"<redacted>"
;;
