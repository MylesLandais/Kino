defmodule Kino.Repo do
  use Ecto.Repo,
    otp_app: :kino,
    adapter: Ecto.Adapters.Postgres
end
