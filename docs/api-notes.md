# Griffin API notes

What we learned building this client (docs read 2026-10-13, OpenAPI version
`2026-07-09` from `https://docs.griffin.com/openapi/openapi-2026-07-09.yaml`, plus
live calls against a sandbox organization).

## Base URL and versioning

- One host for sandbox and live: `https://api.griffin.com`. The organization, not the
  host, decides the mode: `organization-mode` is `test-mode` (sandbox) or `live-mode`.
  Sandbox API keys start with `g-test-`.
- Version is a path prefix, `/v0`. The OpenAPI file lists paths without it
  (`/index`), while every link the API returns includes it (`/v0/index`).
- Compatibility promise: keys are only added to responses, never removed or
  re-purposed within a version. Decoders therefore ignore unknown fields.

## Authentication

- `Authorization: GriffinAPIKey <key>` on every request. `Basic` is not supported.
- `Accept: application/json`; `Content-Type: application/json` when there is a body.
  Responses come back as `application/json;charset=utf-8`.
- `GET /v0/ping` answers `204` with no body; `GET /v0/security/public-keys` needs no key.

## Message signatures (RFC 9421)

- Mandatory for live organizations, optional in the sandbox (an organization toggle
  can enforce them). Signed requests are always validated, even when not enforced.
- Ed25519 only (`alg="ed25519"`). The public key is registered in the web app
  (Team admin role); the app shows the `keyid`. There is no API to register keys.
- Components: `@authority content-digest content-length content-type date @method
  @path @query`; parameters `alg created expires keyid nonce` (expires at most 300 s
  after created, nonce a UUID v4).
- `content-digest: sha-512=:<base64>:` (RFC 9530). For a bodyless request the header may
  be omitted, but the component is still signed (as the empty string); this client
  always sends the digest of the empty body instead.
- `POST /v0/security/message-signature/verify` (any method) checks a signature without
  side effects. Unsigned: `401 missing-or-malformed-signature-input`; unknown key:
  `401 unknown-signing-key-id`; missing components: `401 missing-required-components`
  with the list in `detail`.
- Cross-checked: a request signed by `Http_signature.sign` verifies with the Python
  `http-message-signatures` 0.5.0 library, the one Griffin names as its reference.

## Webhooks

- One webhook per organization; it receives every event. Creating, deleting or
  re-pointing it changes organization-wide state, so this client only lists webhooks.
- Deliveries are signed with ES512 (ECDSA P-521 + SHA-512) using keys published as a
  JWKS at `GET /v0/security/public-keys` (`kid` like `griffin-2026-09-28-1`; two keys
  were active on 2026-10-13). Keys are immutable; cache them and refetch on an unknown
  `kid`. The documented example signature is DER encoded (`MIGIAkIA...`), not JOSE
  raw `r||s`; the verifier accepts both.
- Webhook signature components: `date @method @path @authority content-type
  content-length content-digest`, parameters `created expires nonce keyid` (no `alg`).
- Delivery is at least once, unordered. Deduplicate by `event-url`. The events list
  (`organization-events-url`) is the canonical ordered log for reconciliation.

## Pagination, filtering

- Lists return up to 25 items by default; `page[size]` takes 1 to 200. Responses carry
  `links.prev` / `links.next` (relative URLs with opaque `page[after]`/`page[before]`
  cursors, or `null`). Some lists also return `meta.page.total`.
- Follow `links.next` verbatim; any filters of the first request are carried in it.
- `sort=created-at` / `sort=-created-at` (default descending); filters as
  `filter[field][eq]=...` or `filter[field][in][]=...`; `include=beneficiary` on some lists.

## Rate limits

- 50 concurrent in-flight requests per organization; over that, `429` with an empty
  body. No rate window or `Retry-After` was documented or observed. This client caps
  its own concurrency and retries 429 and 5xx with exponential backoff.

## Idempotency

- There are no idempotency keys. Creating a payment is NOT idempotent (a retried
  create makes a second payment, which does nothing until submitted). Submitting is
  idempotent: a repeated submission answers `410 Gone`; then list the payment's
  submissions to learn its state. The client retries only GET/PUT/DELETE and
  submissions, never other POSTs.

## Sandbox behaviour

- New sandbox accounts are funded automatically (docs say £1,000,000; the operational
  account guide says £1,000).
- Payments are never sent to schemes and always succeed; onboarding runs no
  third-party checks and the organization makes the decision itself
  (`can-decide-on-verifications?` is `true`).
- Confirmation of Payee has a simulation endpoint,
  `POST /v0/simulation/organizations/{id}/cop-request/simulate/{type}` (alpha), with
  types such as `full-match`, `close-match-name`, `no-match-name`,
  `account-not-supported`, `account-switched`, `account-not-found`.
- There is no endpoint to simulate an inbound payment from outside; an inbound payment
  is produced by paying from one sandbox account to another (book transfer or FPS to
  its sort code and account number).

## Errors

- Body: `{"errors":[{"title","status","detail","code","links":{"about"}}]}`. `status` is
  a string; `detail` is usually a string but can be a list.
- No request-id header is returned; the client generates one per logical request,
  sends it as `x-request-id` and puts it in every error.

## TLS (security review, 2026-10-13)

- conduit-async 8.0.0 with async_ssl: when cohttp-async gets no `ssl_config` it builds
  one with only the SNI hostname. async_ssl then verifies the chain (`Verify_peer`,
  OpenSSL default CA paths), but nothing compares the certificate's names with the
  host, and conduit's `verify` hook defaults to accepting everything. Measured against
  badssl.com: the default rejects `self-signed`, `expired` and `untrusted-root` but
  ACCEPTS `wrong.host.badssl.com`, i.e. any valid certificate for another domain.
- `Griffin_client.Tls.config` passes `Verify_peer`, an explicit CA bundle
  (`SSL_CERT_FILE` or the usual system/Homebrew paths) and a `verify` hook that
  requires a validated peer certificate and `check_peer_certificate_host`. The
  transport uses it for every HTTPS request; `test/test_tls.ml` checks all four bad
  hosts are rejected and a good one accepted (skipped when offline).
