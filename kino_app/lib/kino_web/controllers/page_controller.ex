defmodule KinoWeb.PageController do
  use KinoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
