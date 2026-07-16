import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/kino start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :kino, KinoWeb.Endpoint, server: true
end

config :kino, KinoWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if database_url = System.get_env("DATABASE_URL") do
  config :kino, Kino.Repo, url: database_url
end

if username = System.get_env("KINO_BOOTSTRAP_ADMIN_USERNAME") do
  password =
    System.get_env("KINO_BOOTSTRAP_ADMIN_PASSWORD") ||
      raise "KINO_BOOTSTRAP_ADMIN_PASSWORD is required with KINO_BOOTSTRAP_ADMIN_USERNAME"

  config :kino, :bootstrap_admin,
    username: username,
    email: System.get_env("KINO_BOOTSTRAP_ADMIN_EMAIL", "#{username}@kino.local"),
    display_name: System.get_env("KINO_BOOTSTRAP_ADMIN_NAME", "Kino Admin"),
    password: password
end

if avatar_dir = System.get_env("KINO_AVATAR_BOOTSTRAP_DIR") do
  config :kino, :avatar_bootstrap_dir, avatar_dir
end

if bucket = System.get_env("KINO_S3_BUCKET") do
  config :kino, :media,
    storage: Kino.Media.Storage.S3,
    storage_bucket: bucket,
    storage_prefix: System.get_env("KINO_S3_PREFIX", "kino/media"),
    s3_endpoint: System.get_env("AWS_ENDPOINT_URL_S3"),
    s3_public_endpoint:
      System.get_env("KINO_S3_PUBLIC_ENDPOINT") || System.get_env("AWS_ENDPOINT_URL_S3"),
    s3_region: System.get_env("AWS_REGION", "us-east-1")
end

if config_env() == :prod and is_nil(System.get_env("KINO_S3_BUCKET")) do
  raise "KINO_S3_BUCKET is required in production; media must use durable object storage"
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :kino, KinoWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/kino_web/router\.ex$",
        ~r"lib/kino_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :kino, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :kino, KinoWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :kino, KinoWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :kino, KinoWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
