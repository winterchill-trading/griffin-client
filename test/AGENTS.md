# AGENTS.md: griffin-client/test

Unit and fixture tests: signatures, transport retries, decoding, client flows over in-memory
fixtures, webhook verification, TLS (skipped offline), model codecs. `fixtures/` holds the
recorded responses. `live/` is the sandbox walk, enabled only with `GRIFFIN_LIVE_TESTS=1`.

Run: `opam exec --switch 5.2.0+ox -- dune build --root .. @griffin-client/runtest`.

Rules:
- Tests run offline by default. A test that needs the network checks the env variable first.
- Never commit a recorded response that contains a real key, account number or customer
  name; scrub before saving a fixture.
- Promote expect output only after reading the diff.
