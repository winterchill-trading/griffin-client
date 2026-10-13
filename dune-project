(lang dune 3.17)

(name griffin-client)

(generate_opam_files true)

(license MIT)

(maintainers "winterchill-trading")

(authors "winterchill-trading")

(source
 (github winterchill-trading/griffin-client))

(package
 (name griffin-client)
 (synopsis "Async client and CLI for the Griffin banking API")
 (description
  "Typed Griffin API resources (organization, legal persons, bank accounts, payments, payees, Confirmation of Payee, events), hypermedia index navigation, RFC 9421 request signing and webhook signature verification.")
 (depends
  (ocaml
   (>= 5.2))
  dune
  core
  core_unix
  async
  async_ssl
  cohttp
  cohttp-async
  conduit-async
  uri
  yojson
  ppx_jane
  ppx_yojson_conv
  ppx_yojson_conv_lib
  cryptokit
  zarith
  base64))
