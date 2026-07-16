# Kino

Kino is a Phoenix LiveView theater with chat-driven media ingestion and synchronized playback state.

## NixOS development

Kino uses a Nix development shell so Elixir and the asset compilers are native to NixOS. It expects the host PostgreSQL service to accept peer-authenticated Unix-socket connections for the current user.

```bash
./launch.sh
```

The launcher enters `nix develop` when necessary, verifies PostgreSQL, installs dependencies, creates and migrates the database, builds assets, and starts Phoenix at <http://localhost:4000>.

Use `./launch.sh --setup-only` to prepare the project without starting the server. Generated files under `kino_app/priv/static/assets/` are intentionally ignored.

## Validation

```bash
nix develop "path:$PWD" -c bash -lc 'cd kino_app && mix precommit'
./scripts/check-assets.sh
```

The Figma/React design source is preserved under `prototypes/figma-theater/`; Phoenix LiveView in `kino_app/` is the production implementation.
