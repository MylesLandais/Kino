defmodule Kino.Media.LinkProvider do
  @moduledoc "Provider contract for cross-platform recording discovery."

  @callback search(%{artist: String.t(), title: String.t()}) ::
              {:ok, [map()]} | {:error, term()}

  @callback search(%{artist: String.t(), title: String.t()}, term()) ::
              {:ok, [map()]} | {:error, term()}

  @optional_callbacks search: 2
end
