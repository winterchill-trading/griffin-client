# AGENTS.md: griffin-client/.github

- `workflows/ci.yml`: checkout, the shared `ox-setup` action, `dune build`, `dune test`, then
  the reusable obj-magic workflow from `winterchill-trading/infra`. The live walk is not run.
- Concurrency is `cancel-in-progress: true`; push once per finished change.
- To check a run: one `gh run list --limit 1`, then at most one `gh run watch <id>
  --exit-status`. Never poll.
