defmodule KinoWeb.AdminAvatarLive do
  use KinoWeb, :live_view
  alias Kino.{Accounts, Avatar}

  def mount(_params, session, socket) do
    user = Accounts.user_for_session(session["auth_token"])

    if Accounts.allowed?(user, "avatar:manage") do
      socket =
        socket
        |> assign(
          current_scope: %{user: user},
          assets: Avatar.list_assets(),
          profile: Avatar.active_profile(),
          error: nil
        )

      {:ok,
       allow_upload(socket, :asset,
         accept: ~w(.vrm .fbx),
         max_entries: 1,
         max_file_size: 120_000_000
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Administrator permission required")
       |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("upload", params, socket) do
    results =
      consume_uploaded_entries(socket, :asset, fn %{path: path}, entry ->
        Avatar.put_asset(path, entry.client_name, params, socket.assigns.current_scope.user)
      end)

    case results do
      [{:ok, _}] ->
        Accounts.audit("avatar_uploaded", socket.assigns.current_scope.user)
        {:noreply, refresh(socket)}

      [error] ->
        {:noreply, assign(socket, error: inspect(error))}

      [] ->
        {:noreply, assign(socket, error: "Choose a VRM or FBX file")}
    end
  end

  def handle_event("profile", params, socket) do
    attrs =
      Map.take(
        params,
        ~w(model_asset_id idle_asset_id camera_distance lip_sync_mode mouth_gain mouth_smoothing)
      )
      |> Map.merge(%{
        "enabled" => params["enabled"] == "true",
        "look_at_camera" => params["look_at_camera"] == "true"
      })

    case Avatar.update_profile(attrs) do
      {:ok, _} ->
        Accounts.audit("avatar_profile_updated", socket.assigns.current_scope.user)
        {:noreply, refresh(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, error: inspect(changeset.errors))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Avatar.delete_asset(id) do
      {:ok, _} ->
        Accounts.audit("avatar_deleted", socket.assigns.current_scope.user, %{asset_id: id})
        {:noreply, refresh(socket)}

      {:error, :referenced} ->
        {:noreply,
         assign(socket, error: "Select a different active model/idle clip before deleting")}

      error ->
        {:noreply, assign(socket, error: inspect(error))}
    end
  end

  defp refresh(socket),
    do: assign(socket, assets: Avatar.list_assets(), profile: Avatar.active_profile(), error: nil)

  def render(assigns) do
    models = Enum.filter(assigns.assets, &(&1.kind == "model"))
    animations = Enum.filter(assigns.assets, &(&1.kind == "animation"))
    assigns = assign(assigns, models: models, animations: animations)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="admin-shell" id="admin-avatar">
        <header class="admin-head">
          <div>
            <a href={~p"/"}>KINO</a><h1>Avatar studio</h1>
          </div><a href={~p"/admin/users"}>users & access →</a>
        </header>
        <p :if={@error} class="admin-error">{@error}</p>
        <div class="admin-grid">
          <section class="admin-card">
            <h2>Upload asset</h2>
            <form phx-submit="upload" id="avatar-upload-form">
              <.live_file_input upload={@uploads.asset} /><label>Label<input name="label" /></label><label>Description<textarea name="description"></textarea></label><label>Tags<input
                name="tags"
                placeholder="wave, greeting"
              /></label><button>upload to object storage</button>
            </form>
          </section>
          <section class="admin-card">
            <h2>Active profile</h2>
            <form phx-submit="profile" id="avatar-profile-form">
              <label>Model<select name="model_asset_id"><option value="">none</option><option
                :for={a <- @models}
                value={a.id}
                selected={@profile.model_asset_id == a.id}
              >
                {a.label}
              </option></select></label>
              <label>Idle animation<select name="idle_asset_id"><option value="">none</option><option
                :for={a <- @animations}
                value={a.id}
                selected={@profile.idle_asset_id == a.id}
              >
                {a.label}
              </option></select></label>
              <label>Camera distance<input
                name="camera_distance"
                type="number"
                step="0.1"
                min="0.8"
                max="4.5"
                value={@profile.camera_distance}
              /></label>
              <label>Mouth gain<input
                name="mouth_gain"
                type="number"
                step="0.1"
                value={@profile.mouth_gain}
              /></label>
              <label>Smoothing<input
                name="mouth_smoothing"
                type="number"
                step="0.05"
                value={@profile.mouth_smoothing}
              /></label>
              <label>Mode<select name="lip_sync_mode"><option
                value="viseme"
                selected={@profile.lip_sync_mode == "viseme"}
              >
                viseme
              </option><option value="amplitude" selected={@profile.lip_sync_mode == "amplitude"}>
                amplitude
              </option></select></label>
              <input type="hidden" name="enabled" value="false" /><label class="auth-check"><input
                type="checkbox"
                name="enabled"
                value="true"
                checked={@profile.enabled}
              /> enabled</label>
              <input type="hidden" name="look_at_camera" value="false" /><label class="auth-check"><input
                type="checkbox"
                name="look_at_camera"
                value="true"
                checked={@profile.look_at_camera}
              /> look at camera</label>
              <button>save profile</button>
            </form>
          </section>
        </div>
        <section class="admin-card">
          <h2>Catalog</h2><div class="asset-list">
            <article :for={asset <- @assets} id={"avatar-asset-#{asset.id}"}>
              <div>
                <span>{asset.kind}</span><strong>{asset.label}</strong><small>{asset.format} · {Float.round(
                  asset.byte_size / 1_048_576,
                  2
                )} MB</small><p>{asset.description}</p>
              </div><button phx-click="delete" phx-value-id={asset.id}>delete</button>
            </article>
          </div>
        </section>
      </main>
    </Layouts.app>
    """
  end
end
