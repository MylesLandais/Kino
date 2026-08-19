defmodule KinoWeb.ChannelCase do
  @moduledoc """
  Test case for Phoenix channel tests with Kino DB sandbox setup.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint KinoWeb.Endpoint
      use KinoWeb, :verified_routes

      import Phoenix.ChannelTest
      import KinoWeb.ConnCase, only: [register_and_log_in_user: 2]
    end
  end

  setup tags do
    Kino.DataCase.setup_sandbox(tags)
    :ok
  end
end
