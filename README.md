# Kino

Kino is a Phoenix LiveView theater with chat-driven media ingestion and synchronized playback state.

## Nix development

Kino uses a Nix **FHS** development shell so Elixir, Node, esbuild/tailwind, yt-dlp, and PostgreSQL 19 run with a normal `/lib` layout. That avoids the usual Nix "missing shared library" failures from Mix/npm native binaries.

The flake also starts a **user-space PostgreSQL 19** cluster with SQL/PGQ property graph queries (`CREATE PROPERTY GRAPH` / `GRAPH_TABLE`) over the music ontology tables. Unix-socket peer auth is used; the socket directory is exported as `PGHOST`.

**Secrets come from OpenBao** (`bao` in the FHS shell), not from files in this repo. Point the CLI at your cluster with `BAO_ADDR` / `BAO_TOKEN` (Vault-compatible `VAULT_*` names also work). Set `KINO_OPENBAO_PATH` to a KV path whose fields are the usual Kino env names (`SECRET_KEY_BASE`, `AWS_*`, `SPOTIFY_*`, …); `./launch.sh` and Cloud Agent start source `scripts/openbao-env.sh` and export them. Local Postgres/dev still starts when OpenBao is unset.

```bash
./launch.sh
```

The launcher enters `nix run .#fhs` when necessary, starts PostgreSQL 19 if needed, installs dependencies, creates and migrates the database, builds assets, and starts Phoenix at <http://localhost:4000>.

```bash
./launch.sh --setup-only          # deps, database, assets; no server
nix develop                       # interactive FHS shell
nix run .#fhs -- mix test         # run a command inside the FHS shell
direnv allow                      # optional: auto-enter the FHS shell
./scripts/postgres.sh status      # from inside the FHS shell
```

Generated files under `kino_app/priv/static/assets/` are intentionally ignored.

## Validation

```bash
nix run "path:$PWD#fhs" -- bash -lc 'cd kino_app && mix precommit'
./scripts/check-assets.sh
```

The Figma/React design source is preserved under `prototypes/figma-theater/`; Phoenix LiveView in `kino_app/` is the production implementation.
