defmodule Kino.Media.Storage do
  @moduledoc "Durable media object-store boundary."

  @callback put_file(String.t(), String.t()) ::
              {:ok, %{etag: String.t() | nil}} | {:error, term()}
  @callback exists?(String.t()) :: boolean()
  @callback public_url(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, term()}

  def impl, do: Application.fetch_env!(:kino, :media)[:storage]
end
