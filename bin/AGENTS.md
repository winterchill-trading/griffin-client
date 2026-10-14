# AGENTS.md: griffin-client/bin

The `griffin` command (`main.ml`). Every command prints JSON, or sexps with `-sexp`;
`-verbose` logs each HTTP attempt to stderr with request id, path, status and latency, never
headers or bodies. Subcommands and examples are in `../README.md`.

Build: `opam exec --switch 5.2.0+ox -- dune build --root .. @griffin-client/all`.

Rules:
- Read the key from the environment through `Config.of_env`; never take it as a flag.
- `-verbose` output must not include headers or bodies. Check that when adding logging.
