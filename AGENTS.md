# AGENTS.md: griffin-client

## Purpose

Async OxCaml client and CLI for a UK banking-as-a-service API: legal persons and onboarding,
bank accounts, payments, payees, Confirmation of Payee, events and webhooks. Sandbox by
default. It follows the hypermedia links from the index resource rather than hard-coded
paths.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The library `griffin-client` (module `Griffin_client`): config, secrets, transport, TLS, model, client, request signing (see `lib/AGENTS.md`) |
| `bin/` | The `griffin` command: `index`, `org`, `accounts`, `payments`, `cop`, `events`, `webhooks`, `keys` and more (see `bin/AGENTS.md`) |
| `test/` | Unit and fixture tests; `test/fixtures/` holds recorded responses; `test/live/` is the sandbox walk (see `test/AGENTS.md`) |
| `docs/` | `api-notes.md`: what the API does that the docs do not say (see `docs/AGENTS.md`) |
| `.github/` | CI workflow and the shared obj-magic check (see `.github/AGENTS.md`) |
| `README.md` | Quick start, environment, endpoint coverage, known gaps |
| `.env.example` | Variable names for a local `.env`. The `.env` file itself is gitignored and must not be committed |
| `dune-project` | Package metadata; edit this, not the generated `griffin-client.opam` |

## Build, test

Run from this repository. The workspace root is one level up, so every command takes
`--root ..`.

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @griffin-client/all
opam exec --switch 5.2.0+ox -- dune build --root .. @griffin-client/runtest
```

Parallel work with another agent: prefix each with `DUNE_BUILD_DIR=_build-griffin-client`.

The live sandbox walk is opt-in: it needs `GRIFFIN_LIVE_TESTS=1` and a sandbox key in the
environment. Without them it is skipped, and `dune test` still passes.

Standalone (outside the workspace): the org opam repository is the target (see
`../specs/repos/opam-repository.md`). Until then, `opam install . --deps-only --with-test`
then `dune build`. The switch must be `5.2.0+ox`.

## Conventions

- Format only this repository: `dune build --root .. @griffin-client/fmt --auto-promote`.
  Never run `dune fmt` at the workspace root.
- Every module has an `.mli`. Consume siblings by public opam name.
- Secrets never reach logs or errors: keys are held in `Secret`, and `Config` prints them as
  `<redacted>`. Keep it that way in any new field.
- Keys other than sandbox keys are refused unless the caller passes `~live:true`. Do not
  add a path around that check.
- Enumerations are strings, not variants, because the API adds values within its version.
  Keep them that way.
- Comments for humans at non-obvious choices (signature bases, TLS checks).

## Dependencies and dependents

No sibling dependencies in CI. `Ed25519` and `P521` are written over Zarith because no
elliptic-curve library builds on the OxCaml switch.

## CI

`.github/workflows/ci.yml`: checkout, the shared `ox-setup` action, `dune build`, `dune test`,
then the reusable obj-magic workflow from `../infra`. The live walk is not run in CI.

To check a run: one `gh run list --limit 1`, then at most one `gh run watch <id>
--exit-status`. Never poll.

## Pitfalls

- Sign `Uri.path_and_query` as cohttp writes it, not the link text. `Uri.to_string`
  percent-encodes brackets in `page[after]=`; the API accepts that, but the signature base
  must match the bytes sent.
- The HTTP `date` header's day and month need `String.lowercase |> String.capitalize`
  before they go into the signature base, or the base differs from what other tools write.
- The default cohttp TLS configuration accepts a wrong host name. `Tls.config` makes an
  explicit configuration that rejects the self-signed, expired, untrusted-root and
  wrong-host cases; the TLS test checks them.
- Signed requests are not yet accepted end to end: the signature format is verified against
  a reference library, but no key is registered for the sandbox. See the known gaps.
- The live walk creates real sandbox records (legal persons, accounts, payments). Run it on
  purpose.

## Where to read more

- `README.md`: quick start, environment, endpoint coverage, known gaps, tests.
- `docs/api-notes.md`: API behaviour the reference does not state.
- `../specs/repos/griffin-client.md`: status.
- `../oxcaml-claude-skills/GOTCHAS.md`: the griffin-client and banking sections.
- `../oxcaml-claude-skills/skills/banking-standards/`: the rules for banking code.
- `../oxcaml-claude-skills/AGENTS.md`: workspace-wide guide.

## Never do

- Commit `.env` or any key, or print the value of a secret in a log, test output or error.
- Use a non-sandbox key, or pass `~live:true`, from a test or a script in this repository.
- Install opam packages that change the compiler or `core`, `base`, `async`, `ppx_jane`
  on the shared `5.2.0+ox` switch. Dry-run first: `opam install --switch 5.2.0+ox --dry-run <pkg>`.
- Publish, tag or release.
- Poll CI in loops.
