# AGENTS.md: griffin-client/lib

The `griffin-client` library (module `Griffin_client`).

| Module | Holds |
| --- | --- |
| `Config` | `of_env ?live`: base URL (sandbox by default), API key, optional signing key |
| `Secret` | API key and signing material, kept out of logs and errors |
| `Transport` | HTTP: auth, optional request signing, retries with backoff for idempotent calls, in-flight cap, request ids |
| `Tls` | Peer and host-name verification against an explicit CA bundle |
| `Index`, `Links` | The hypermedia entry point and the link relations |
| `Model` | Typed records with stable JSON codecs; unknown fields are ignored |
| `Page` | List pages with `links.next` and `links.prev` cursors |
| `Client` | `connect` and the typed operations; `get` for any link; `fold` and `pipe` over pages |
| `Claims` | Request bodies for a sandbox individual legal person |
| `Http_signature` | RFC 9421 signing and verification with RFC 9530 digests |
| `Ed25519`, `P521` | Signature algorithms over Zarith |

Build: `opam exec --switch 5.2.0+ox -- dune build --root .. @griffin-client/all`.

Rules:
- A new endpoint gets a typed model, a fixture under `test/fixtures/`, and a line in the
  README coverage table.
- Retries apply to idempotent calls only. A payment submission is not retried.
- Keep `Secret` the only holder of key material.
