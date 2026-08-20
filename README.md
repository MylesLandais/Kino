# Kino

Kino is a Phoenix LiveView theater with chat-driven media ingestion and synchronized playback state.

## Nix development

This repo uses a lean Nix flake with auto-discovered Elixir packages. No FHS is required.

* **Elixir/Erlang:** `beam27Packages` with `elixir_1_17` (OTP 27) via `devShells.default`. Satisfies all apps (`kino_app`/`harness` `~> 1.17`, `dnd_app`/`image_graph_vectorizer` `~> 1.14`).
* **Node:** `nodejs_24` for Phoenix assets (`kino_app/assets`).
* **DB/Media:** `postgresql_19` (user-space `PGHOST` socket), `yt-dlp`+`ffmpeg` (`KINO_YTDLP_BIN`), `tailwindcss_4`/`esbuild` (`MIX_*_PATH` via Nix, no stub-ld).
* **Tooling:** `git`, `gnumake`, `gcc`, `pkg-config`, `inotify-tools` for `file_system`/`phoenix_live_reload`, `docker` + `docker-load` helper.

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
ls result/bin/          # mix releases expose `bin/<pname> start` (kino_app → bin/kino)
result/bin/kino start
```

Docker images are built per-app via `nix/mkImage.nix` and exposed as `.#<pname>-docker` (alias `.#<pname>-dockerImage`):

```bash
nix build .#kino_app-docker        # also .#kino_app-dockerImage
nix build .#harness-docker
nix build .#dnd_app-docker
nix build .#image_graph_vectorizer-docker

# load all images into docker daemon
./scripts/docker-load.sh            # builds + docker load < result
./scripts/docker-load.sh kino_app   # single app
# inside nix develop, also available as:
docker-load                         # all apps
docker-load kino_app                # single app
docker images | grep kino_app
docker run --rm -p 4000:4000 kino_app:latest
```

`default.nix` per app uses `beam.mixRelease` + `beam.fetchMixDeps` and calls `mkImage` for flexible docker deps (e.g. `extraContents = [ pkgs.nodejs_24 ]`):

```nix
{ pkgs, beam ? pkgs.beam27Packages }:
let
  release = beam.mixRelease {
    pname = "kino_app";
    version = "0.1.0";
    src = ./.;
    mixFodDeps = beam.fetchMixDeps {
      pname = "kino_app"; version = "0.1.0"; src = ./.;
      hash = "sha256-..."; # run `nix build .#kino_app` once to get the expected hash
    };
  };
  mkImage = import ../nix/mkImage.nix { inherit pkgs; };
  dockerImage = mkImage {
    pname = "kino_app";
    package = release;
    bin = "kino"; # release binary (mix app :kino)
    exposedPorts = { "4000/tcp" = {}; };
    extraContents = [ pkgs.nodejs_24 pkgs.yt-dlp pkgs.ffmpeg ]; # flexible runtime deps
    env = [ "KINO_YTDLP_BIN=/bin/yt-dlp" ];
  };
in
release // { passthru = (release.passthru or {}) // { inherit dockerImage; }; }
# -> exposes `nix build .#kino_app` and `nix build .#kino_app-docker` / `.#kino_app-dockerImage`
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
  packages.nix      # auto-discovers every `*/default.nix`, exposes `packages.<pname>` + `packages.default` + `packages.<pname>-docker`
  mkImage.nix       # helper for dockerTools.buildLayeredImage (flexible extraContents, ports, etc.)
  # add more helpers here as needed (e.g. postgres.nix) and import from flake.nix/shell.nix
```

Add a new app: `mkdir my_app && cp kino_app/default.nix my_app/default.nix` (adjust `pname`), it appears automatically via `nix/packages.nix`. For larger flakes, add more modules under `nix/` and import them from `flake.nix` or `shell.nix` instead of growing the flake inline.

### Scripts

* `./launch.sh` – re-execs via `nix develop` if needed, starts Postgres (`scripts/postgres.sh`), runs `mix setup` and `mix phx.server` for `kino_app` (`--setup-only` for CI)
* `scripts/postgres.sh` – user-space PostgreSQL 19 (now via `postgresql_19` from `shell.nix`, not FHS); supports `start|stop|status`, auto re-execs with `nix develop` if `initdb` not on PATH
* `scripts/with-fhs.sh` – kept for compat, now delegates to `nix develop --command`
* `scripts/docker-load.sh` – builds Nix docker images (`nix build .#<pname>-docker`) and `docker load`s them (`./scripts/docker-load.sh` for all, or `./scripts/docker-load.sh kino_app`); inside `nix develop` also as `docker-load`
* `scripts/openbao-env.sh` / `scripts/nix-env.sh` / `scripts/pg-env.sh` – env helpers

Secrets still come from OpenBao (`BAO_ADDR`/`BAO_TOKEN`, `KINO_OPENBAO_PATH`), not committed files. For Neo4j, run your own service or `docker run neo4j:5-community`.

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
