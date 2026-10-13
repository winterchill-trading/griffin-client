# griffin-client

An [OxCaml](https://oxcaml.org) / Async client library and CLI for the
[Griffin](https://docs.griffin.com) banking API (UK banking as a service: legal persons
and onboarding, bank accounts, payments, payees, Confirmation of Payee, events and
webhooks). Sandbox by default.

- Navigates by hypermedia links from `GET /v0/index` instead of hardcoding paths.
- Typed records for every resource, with stable JSON codecs (unknown fields ignored,
  round trips tested on recorded sandbox responses).
- Retries 429 and 5xx with exponential backoff for idempotent calls only, caps
  in-flight requests, tags every request with a client request id, never prints the
  API key.
- Optional RFC 9421 request signing (Ed25519, SHA-512 content digests), required by
  live organizations.
- Webhook verification against Griffin's published ES512 (P-521) keys.
- TLS with certificate host-name checking (see [docs/api-notes.md](docs/api-notes.md#tls-security-review-2026-10-13)).

## Quick start

```sh
opam switch create 5.2.0+ox --repos ox=git+https://github.com/oxcaml/opam-repository.git,default
opam install . --deps-only --with-test
dune build && dune test

cp .env.example .env        # fill in GRIFFIN_API_KEY (a g-test- sandbox key)
set -a; . ./.env; set +a
dune exec griffin -- index
dune exec griffin -- accounts list -page-size 5
dune exec griffin -- accounts open -product Operational -name "My account"
dune exec griffin -- payments create /v0/bank/accounts/ba.XXX -amount 1.00 \
  -sort-code 040004 -account-number 12345678 -holder "Example Payee"
dune exec griffin -- payments submit /v0/payments/pm.XXX
dune exec griffin -- cop simulate -name "Example Payee" -sort-code 040004 \
  -account-number 12345678 -outcome close-match-name
dune exec griffin -- events -sexp
```

Every command prints JSON (or sexps with `-sexp`); `-verbose` logs each HTTP attempt
(request id, path, status, latency; never headers or bodies) to stderr.

```ocaml
let%bind.Deferred.Or_error config = Deferred.return (Griffin_client.Config.of_env ()) in
let%bind.Deferred.Or_error client =
  Griffin_client.Client.connect (Griffin_client.Transport.create config)
in
Griffin_client.Client.bank_accounts client
```

## Environment

| Variable | Required | Meaning |
|---|---|---|
| `GRIFFIN_API_KEY` | yes | API key. Keys not starting with `g-test-` are refused unless `~live:true` / `-live`. |
| `GRIFFIN_API_BASE_URL` | no | Default `https://api.griffin.com`. |
| `GRIFFIN_SIGNING_KEY` | no | Ed25519 private key: PKCS#8 PEM, or the 32-byte seed in base64 or hex. |
| `GRIFFIN_SIGNING_KEY_ID` | with the key | The `keyid` the Griffin app shows after registering the public key. |
| `GRIFFIN_LIVE_TESTS` | no | `1` lets `dune test` run the live sandbox walk (needs the key). |
| `SSL_CERT_FILE` | no | CA bundle; otherwise the usual system and Homebrew paths. |

Credentials are read only from the environment. Keep them in the gitignored `.env`.
`Config.t` and errors print the key as `<redacted>`, and error bodies are scrubbed of it.

## Library modules

| Module | Purpose |
|---|---|
| `Config` | Environment config, sandbox guard, signing key parsing |
| `Transport` | HTTP calls: auth header, signing, retries, throttle, request ids, `Api_error` |
| `Tls` | cohttp-async SSL config with host-name verification |
| `Index`, `Links` | Hypermedia entry point and link relations |
| `Model` | Typed resources (`Organization`, `Legal_person`, `Bank_account`, `Payment`, ...) |
| `Page` | List pages with `links.next` / `links.prev` cursors |
| `Client` | Operations; `fold` and `pipe` over every page |
| `Claims` | Legal person request bodies (sandbox individual with all Verify claims) |
| `Http_signature` | RFC 9421 signing and verification, RFC 9530 digests |
| `Ed25519`, `P521` | Signature algorithms over Zarith (no EC library builds on the ox switch) |
| `Webhook` | Verify deliveries; JWKS key set with refresh on unknown `keyid` |
| `Api_error` | Decoded Griffin error bodies; `status_of_error` |

## Endpoint coverage

"Live" means exercised against the Griffin sandbox on 2026-10-13 by
`test/live/live.exe` or the CLI; "fixtures" means decoded from recorded, redacted
sandbox responses in `test/fixtures/` on every `dune test`.

| Area | Endpoint (via link relation) | Client function | Verified |
|---|---|---|---|
| Navigation | `GET /v0/index` | `Client.connect`, `Index.fetch` | live, fixtures |
| Organization | `GET organization-url` | `Client.connect` (refuses `live-mode` without opt-in) | live, fixtures |
| Legal persons | `GET/POST organization-legal-persons-url`, `GET legal-person-url` | `legal_persons`, `create_legal_person`, `legal_person` | live, fixtures |
| Onboarding | `GET organization-workflows-url`, `POST legal-person-verifications-url`, `GET verification-url` | `workflows`, `start_verification`, `verification` | live, fixtures |
| Decisions | `GET/POST legal-person-decisions-url` | `decisions`, `decide` | GET live (sandbox auto-accepted, so `decide` was not needed); fixtures |
| Products | `GET organization-bank-account-products-url` | `bank_products` | live, fixtures |
| Accounts | `POST bank-account-product-accounts-url`, `GET account-url`, `GET organization-bank-accounts-url` | `open_account`, `wait_until_open`, `bank_account`, `bank_accounts` | live, fixtures |
| Transactions | `GET account-transactions-url` | `transactions` | live, fixtures |
| Payments | `POST/GET account-payments-url` | `create_payment`, `payments` | live, fixtures |
| Submissions | `POST/GET payment-submissions-url`, `GET submission-url` | `submit_payment` (410 -> `Already_submitted`), `submission` | live, fixtures |
| Admissions | `GET account-admissions-url` | `admissions` | live, fixtures |
| Inbound payment | FPS from one sandbox account to another's sort code / account number | live test step | live |
| Payees | `GET/POST legal-person-bank-payees-url` | `payees`, `create_payee`, pay with `Creditor.Payee` | live, fixtures |
| Confirmation of Payee | `POST <organization-url>/cop-request` | `confirm_payee` | live (match), fixtures |
| CoP simulation | `POST /v0/simulation/organizations/{id}/cop-request/simulate/{type}` | `simulate_confirm_payee` | live (close-match, no-match, account-not-found 400), fixtures |
| Events | `GET organization-events-url` | `events`, `fold`, `pipe` | live, fixtures |
| Webhooks | `GET organization-webhooks-url` | `webhooks` (read-only) | live, fixtures |
| Webhook keys | `GET /v0/security/public-keys` | `Webhook.Keys.fetch` | live, fixtures |
| Webhook signatures | ES512 RFC 9421 on deliveries | `Webhook.verify` | own P-521 signatures in Griffin's documented format; OpenSSL vectors |
| Request signing | `POST /v0/security/message-signature/verify` | `Transport` with `GRIFFIN_SIGNING_KEY`, `griffin check-signature` | format accepted live (`unknown-signing-key-id` for an unregistered key, same answer as the reference Python library); reference library verifies our signatures offline |
| Pagination | `page[size]`, `links.next` | `with_page_size`, `fold` | live (8 accounts, two per page), fixtures |
| TLS | badssl.com hosts | `Tls.config` | self-signed, expired, wrong host, untrusted root rejected |

## Known gaps

- **Signed requests end to end**: registering a public key needs the Griffin web app
  (Team admin); there is no API for it, and no key was registered for this sandbox. The
  signature format is verified (reference library cross-check, live
  `unknown-signing-key-id` answer), but no signed request has been accepted live. Note
  that in the sandbox a request signed with an unknown key is rejected
  (`signature-verification-rejected`) even though signing is not enforced.
- **Real webhook deliveries**: no endpoint here receives Griffin's webhooks, and the
  organization's only webhook belongs to another integration, so creating, testing or
  re-pointing it was not done. Verification is tested with our own P-521 key in
  Griffin's documented header format.
- **Not wrapped**: bank account closure, restrictions, holds, statements, mandates and
  direct debits, claims (fraud), memberships, users, roles, API keys, invitations,
  account and payment search, open banking consents, onboarding applications (the
  Reliance/Outsourced flows), payment PATCH (approvals). `Client.get` and `Client.page`
  reach any of them by link.
- **Book transfers** are supported (`~scheme:`Book_transfer`) but the live walk uses
  Faster Payments for both inbound and outbound.
- Enumerations (statuses, product classes, event types) are strings, not variants,
  because Griffin adds values within `v0`.

## Tests

- `dune test`: unit and fixture tests (signatures, transport retries, decoding,
  client flows over in-memory fixtures, webhook verification) plus the TLS check
  (skipped offline) and the live walk (skipped without `GRIFFIN_LIVE_TESTS=1`).
- `GRIFFIN_LIVE_TESTS=1 dune test` (with `.env` loaded) walks: index -> organization
  -> create legal person -> verification and decision -> open two operational
  accounts -> inbound FPS payment into one -> list its transactions and admissions ->
  outbound payment and the 410 on resubmission -> CoP (live and simulated) -> payee
  and a payment to it -> events, webhooks, signing keys -> pagination.

See [docs/api-notes.md](docs/api-notes.md) for what we learned about the API.
