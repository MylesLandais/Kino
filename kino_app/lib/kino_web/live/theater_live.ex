defmodule KinoWeb.TheaterLive do
  @moduledoc """
  Minimal LiveView shell for the theater route.

  Authenticated users get a React/Tint mount point; guests see the join form.
  All theater interaction flows through the `/agent` websocket channel.
  """

  use KinoWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    user = Kino.Accounts.user_for_session(session["auth_token"])
    username = user && user.username

    if is_nil(username) do
      {:ok, assign(socket, page_title: "Join", username: nil, current_scope: nil)}
    else
      {:ok,
       socket
       |> assign(:page_title, "Theater")
       |> assign(:username, username)
       |> assign(:current_scope, %{user: user})}
    end
  end

  @impl true
  def render(%{username: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="join-shell flex min-h-dvh items-center justify-center bg-tint-bg p-6">
        <form
          action="/session"
          method="post"
          class="w-full max-w-sm rounded-xl border border-tint-border bg-tint-panel p-6 shadow-sm"
          id="join-form"
        >
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <strong class="text-lg font-semibold text-tint-ink">KINO</strong>
          <p class="mt-2 text-sm text-tint-muted">pick a handle to enter the theater</p>
          <input
            name="username"
            placeholder="handle"
            autocomplete="off"
            autofocus
            minlength="2"
            maxlength="24"
            pattern="[a-zA-Z0-9_\-]+"
            required
            class="mt-4 w-full rounded-lg border border-tint-border bg-tint-surface px-3 py-2 text-sm text-tint-ink outline-none focus-visible:ring-2 focus-visible:ring-tint-accent"
          />
          <button
            type="submit"
            class="mt-4 w-full rounded-lg bg-tint-accent px-3 py-2 text-sm font-medium text-white transition hover:opacity-90"
          >
            enter ›
          </button>
        </form>
      </main>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="tint-theater"
        class="tint-theater-root"
        phx-hook="TintTheater"
        phx-update="ignore"
        data-username={@username}
      />
    </Layouts.app>
    """
  end
end
