# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :kino,
  ecto_repos: [Kino.Repo],
  generators: [timestamp_type: :utc_datetime]

config :kino, Oban,
  engine: Oban.Engines.Basic,
  repo: Kino.Repo,
  queues: [media: 2, enrichment: 4, catalog: 2]

config :kino, :media,
  cache_dir: nil,
  ytdlp: Kino.Media.YtDlp.Cli,
  ytdlp_bin: "yt-dlp",
  storage: Kino.Media.Storage.Local,
  storage_bucket: nil,
  storage_prefix: "kino/media"

config :kino, :music_link_providers,
  bandcamp: {Kino.Media.LinkProvider.Http, :bandcamp},
  soundcloud: {Kino.Media.LinkProvider.Http, :soundcloud},
  deezer: {Kino.Media.LinkProvider.Http, :deezer},
  apple_music: {Kino.Media.LinkProvider.Http, :apple_music},
  spotify: {Kino.Media.LinkProvider.Http, :spotify},
  beatport: {Kino.Media.LinkProvider.Http, :beatport},
  discogs: {Kino.Media.LinkProvider.Http, :discogs}

# Configure the endpoint
config :kino, KinoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KinoWeb.ErrorHTML, json: KinoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Kino.PubSub,
  live_view: [signing_salt: "nhAbklTh"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

if path = System.get_env("MIX_ESBUILD_PATH") do
  config :esbuild, path: path, version_check: false
end

if path = System.get_env("MIX_TAILWIND_PATH") do
  config :tailwind, path: path, version_check: false
end

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  kino: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  kino: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
