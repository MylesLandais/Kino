# Kino

Kino is a Phoenix LiveView theater with chat-driven media ingestion and synchronized playback state.

## Nix development

This repo uses a lean Nix flake with auto-discovered Elixir packages. No FHS is required.

* **Elixir/Erlang:** `beam27Packages` with `elixir_1_17` (OTP 27) via `devShells.default`. Satisfies all apps (`kino_app`/`harness` `~> 1.17`, `dnd_app`/`image_graph_vectorizer` `~> 1.14`).
* **Node:** `nodejs_24` for Phoenix assets (`kino_app/assets`).
* **Tooling:** `git`, `gnumake`, `gcc`, `pkg-config`, `inotify-tools` for `file_system`/`phoenix_live_reload`.

```bash
nix develop              # or `direnv allow` with `.envrc` (use flake)
elixir --version         # Elixir 1.17.3 (OTP 27)
mix --version
node --version
```

### Building packages

Each Mix app exposes a `default.nix` and is auto-discovered by `flake.nix` (`readDir` + `default.nix` filter). Adding a new app is:

```bash
mkdir my_app
cp kino_app/default.nix my_app/default.nix  # adjust pname
# next `nix flake show` will list it automatically
```

Available packages (from `nix flake show`):

```bash
nix build .#kino_app                 # Phoenix app (also `nix build` / `nix build .#default`)
nix build .#harness                  # OTP agent harness
nix build .#dnd_app                  # D&D LiveView app (requires Neo4j at runtime)
nix build .#image_graph_vectorizer  # CLIP/Neo4j vectorizer

# inspect outputs
nix flake show
nix build .#kino_app --print-out-paths
ls result/bin/          # mix releases expose `bin/<app> start` etc.
result/bin/kino_app start
```

`default.nix` per app uses `beam.mixRelease` + `beam.fetchMixDeps`:

```nix
{ pkgs, beam ? pkgs.beam27Packages }:
beam.mixRelease {
  pname = "kino_app";
  version = "0.1.0";
  src = ./.;
  mixFodDeps = beam.fetchMixDeps {
    pname = "kino_app"; version = "0.1.0"; src = ./.;
    hash = "sha256-..."; # run `nix build .#kino_app` once to get the expected hash
  };
}
```

After bumping `mix.lock`, re-run `nix build .#<pname>` and copy the `got: sha256-...` hash into the corresponding `default.nix`.

### Development workflow

```bash
# from inside `nix develop`
cd kino_app && mix setup               # deps.get + ecto.setup + assets.setup/build
mix precommit                          # compile --warnings-as-errors + format + test
mix test                               # or Mix test per app
mix phx.server                         # dev server (needs Postgres if DB-dependent)

cd ../harness && mix test
cd ../dnd_app && mix test              # needs Neo4j bolt://localhost:7687
cd ../image_graph_vectorizer && mix test

# run a single command without entering the shell
nix develop -c bash -lc 'cd kino_app && mix test'
```

### Formatting & checks

```bash
nix fmt                  # nixfmt-tree (formats flake.nix + nix/*.nix + all default.nix)
nix flake check          # evaluates packages/devShells/formatter for x86_64-linux
nix develop -c mix format --check-formatted  # Elixir formatter per app
```

Supported systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin` (`x86_64-darwin` was dropped by `nixpkgs` 26.11).

### Nix layout

`flake.nix` is intentionally thin and delegates to `shell.nix` and `nix/` so it stays manageable as the repo grows. `shell.nix` is the source of truth for the dev shell (used by both `nix develop` and `nix-shell`); `nix/` only contains reusable expressions.

```
flake.nix           # entrypoint, imports shell.nix + nix/*.nix (formatter = pkgs.nixfmt-tree)
shell.nix           # mkShell with beam27Packages.elixir_1_17, nodejs_24, etc. (source of truth)
nix/
  packages.nix      # auto-discovers every `*/default.nix`, exposes `packages.<pname>` + `packages.default`
  # add more helpers here as needed (e.g. postgres.nix) and import from flake.nix/shell.nix
```

Add a new app: `mkdir my_app && cp kino_app/default.nix my_app/default.nix` (adjust `pname`), it appears automatically via `nix/packages.nix`. For larger flakes, add more modules under `nix/` and import them from `flake.nix` or `shell.nix` instead of growing the flake inline.

### Legacy scripts

`./launch.sh`, `scripts/postgres.sh`, and OpenBao integration (`BAO_ADDR`/`BAO_TOKEN`, `scripts/openbao-env.sh`) were tied to the old FHS shell and are no longer provided by `flake.nix`. For local Postgres/Neo4j, run your own services or add a `devShells.withPg` overlay. Secrets should still come from env/OpenBao, not committed files.

Generated files under `kino_app/priv/static/assets/` are intentionally ignored.

## Validation

```bash
nix flake check
nix build .#kino_app --no-link
nix develop -c bash -lc 'cd kino_app && mix precommit'
./scripts/check-assets.sh  # if present
```

The Figma/React design source is preserved under `prototypes/figma-theater/`; Phoenix LiveView in `kino_app/` is the production implementation.

The OTP agent harness (DeepSeek/Cordis ideas, not a TypeScript port) lives in `harness/`. See `harness/ARCHITECTURE.md`.
