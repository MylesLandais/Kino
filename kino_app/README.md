# Kino application

Run Kino from the repository root with `./launch.sh`. The root launcher supplies Nix-native Tailwind and esbuild binaries, prepares the local PostgreSQL databases, builds assets, and starts Phoenix.

Application-specific commands can be run with:

```bash
nix develop "path:$PWD/.." -c bash -lc 'cd kino_app && mix test'
```

Production uses durable PostgreSQL and S3-compatible object storage. Configure:

```bash
DATABASE_URL=ecto://user:pass@postgres/maya
KINO_S3_BUCKET=media
AWS_ENDPOINT_URL_S3=http://seaweedfs:8333
KINO_S3_PUBLIC_ENDPOINT=https://objects.example.com
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
```

Downloaded media is uploaded under `kino/media/` before it is marked ready. The local file remains a disposable hot cache; when it is absent, `/media/:cache_key` redirects to a short-lived signed object URL.

Avatar VRM models and Mixamo FBX animations are managed by administrators at `/admin/avatar`. They are stored content-addressably under `kino/avatar/` in the same S3-compatible SeaweedFS bucket. Configure the bucket CORS policy to allow `GET` from the Kino browser origin so Three.js can follow signed object URLs.

An empty development catalog imports Maya's `Yuki.vrm`, `Idle.fbx`, wave, Macarena, and backflip assets from the neighboring `maya-unified/data` checkout and activates Yuki automatically. Set `KINO_AVATAR_BOOTSTRAP_DIR` to use a different Maya-compatible asset directory; an existing profile is never overwritten.

In local development, an empty database is bootstrapped with `admin` / `admin` for compatibility. Change that password before exposing the development server beyond localhost. In production, visit `/setup` to create the first administrator, or set `KINO_BOOTSTRAP_ADMIN_USERNAME` and `KINO_BOOTSTRAP_ADMIN_PASSWORD` before the first boot. Further accounts are invitation-only and are managed at `/admin/users`. Kino keeps opaque, hashed server sessions and permission-based roles separate from Maya's account tables.
