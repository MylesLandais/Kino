defmodule KinoWeb.AdminUsersLive do
  use KinoWeb, :live_view
  alias Kino.Accounts

  def mount(_params, session, socket) do
    user = Accounts.user_for_session(session["auth_token"])

    if Accounts.allowed?(user, "users:manage") do
      {:ok,
       assign(socket,
         current_scope: %{user: user},
         users: Accounts.list_users(),
         invite: nil,
         email: ""
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Administrator permission required")
       |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("invite", %{"email" => email}, socket) do
    {code, _} = Accounts.create_invitation(socket.assigns.current_scope.user, email)
    {:noreply, assign(socket, invite: url(~p"/signup?code=#{code}"), email: "")}
  end

  def handle_event("status", %{"id" => id, "status" => status}, socket) do
    _ = Accounts.suspend_user(socket.assigns.current_scope.user, id, status)
    {:noreply, assign(socket, users: Accounts.list_users())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="admin-shell" id="admin-users">
        <header class="admin-head">
          <div>
            <a href={~p"/"}>KINO</a><h1>Users & access</h1>
          </div><a href={~p"/admin/avatar"}>avatar assets →</a>
        </header>
        <section class="admin-card">
          <h2>Invite operator</h2>
          <form phx-submit="invite" id="invite-form">
            <input
              name="email"
              type="email"
              value={@email}
              placeholder="operator@example.com"
              required
            /><button>create invitation</button>
          </form>
          <p :if={@invite} id="invite-result"><a href={@invite}>{@invite}</a></p>
        </section>
        <section class="admin-card">
          <table>
            <thead>
              <tr>
                <th>User</th><th>Roles</th><th>Status</th><th></th>
              </tr>
            </thead><tbody>
              <tr :for={user <- @users} id={"user-#{user.id}"}>
                <td>
                  <strong>{user.display_name}</strong><small>@{user.username} · {user.email}</small>
                </td><td>{Enum.map_join(user.roles, ", ", & &1.name)}</td><td>{user.status}</td><td>
                  <button
                    :if={user.id != @current_scope.user.id}
                    phx-click="status"
                    phx-value-id={user.id}
                    phx-value-status={if user.status == "active", do: "suspended", else: "active"}
                  >{if user.status == "active", do: "suspend", else: "restore"}</button>
                </td>
              </tr>
            </tbody>
          </table>
        </section>
      </main>
    </Layouts.app>
    """
  end
end
