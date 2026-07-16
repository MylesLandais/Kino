import Config

config :kino, Kino.Repo,
  socket_dir: "/run/postgresql",
  database: "kino_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 4

config :kino, Oban, testing: :manual

config :kino, :media,
  ytdlp: Kino.Media.YtDlpStub,
  storage: Kino.Media.Storage.Local,
  cache_dir: Path.join(System.tmp_dir!(), "kino_media_test"),
  # Resolve inline so tests stay deterministic and inside the DB sandbox.
  resolve_mode: :sync

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kino, KinoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "BT45R6rZUypUYAvZ+LMztbjSrFemLl4aqWp7SRkMVWt5jBsUB0/+n8cRCw2mghWq",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
