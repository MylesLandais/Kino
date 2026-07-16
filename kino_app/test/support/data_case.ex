defmodule Kino.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring access to the
  application's data layer, using the SQL sandbox.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Kino.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Kino.DataCase
    end
  end

  setup tags do
    Kino.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Kino.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
