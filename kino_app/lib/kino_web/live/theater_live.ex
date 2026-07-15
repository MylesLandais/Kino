defmodule KinoWeb.TheaterLive do
  use KinoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    messages = initial_messages()

    {:ok,
     socket
     |> assign(:page_title, "Theater")
     |> assign(:form, to_form(%{"message" => ""}))
     |> assign(:messages, messages)
     |> assign(:approval, Enum.find(messages, &(&1.state == :approval)))
     |> assign(:playback, idle_playback())}
  end

  @impl true
  def handle_event("send", %{"message" => text}, socket) do
    text = String.trim(text)

    socket =
      socket
      |> assign(:form, to_form(%{"message" => ""}))
      |> append_message(message(:user, text, user: "you"))

    if String.starts_with?(text, "/play ") do
      url = text |> String.trim_leading("/play ") |> String.trim()
      job_id = "oban:#{System.unique_integer([:positive])}"
      send(self(), {:pipeline_step, :working, job_id, url})
      Process.send_after(self(), {:pipeline_step, :approval, job_id, url}, 900)

      {:noreply,
       append_message(
         socket,
         message(:agent, "Resolving video metadata…", state: :pending, payload: %{url: url})
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("approve", _params, %{assigns: %{approval: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("approve", _params, socket) do
    approval = socket.assigns.approval

    playback = %{
      id: "queued-video",
      desired_state: :playing,
      observed_state: :buffering,
      title: approval.payload.title,
      requested_by: approval.payload.requested_by,
      duration: approval.payload.duration,
      cache_key: approval.payload.cache_key,
      provider: "seaweedfs/s3"
    }

    Process.send_after(self(), :playback_ready, 1_200)

    {:noreply,
     socket
     |> remove_message(approval.id)
     |> assign(:approval, nil)
     |> assign(:playback, playback)
     |> append_message(
       message(:system, "Now playing: #{approval.payload.title} — approved by host")
     )}
  end

  def handle_event("deny", _params, %{assigns: %{approval: nil}} = socket), do: {:noreply, socket}

  def handle_event("deny", _params, socket) do
    approval = socket.assigns.approval

    {:noreply,
     socket
     |> remove_message(approval.id)
     |> assign(:approval, nil)
     |> append_message(message(:system, "Queue request denied by host"))}
  end

  @impl true
  def handle_info({:pipeline_step, :working, job_id, _url}, socket) do
    {:noreply,
     append_message(
       socket,
       message(:agent, "Cache miss — enqueueing yt-dlp worker",
         state: :working,
         payload: %{job_id: job_id, cache_key: "video:1080p"}
       )
     )}
  end

  def handle_info({:pipeline_step, :approval, job_id, url}, socket) do
    approval =
      message(:agent, "Download complete — awaiting host approval",
        state: :approval,
        payload: %{
          title: "Queued video",
          duration: "—",
          requested_by: "you",
          url: url,
          job_id: job_id,
          cache_key: "video:1080p"
        }
      )

    {:noreply, socket |> append_message(approval) |> assign(:approval, approval)}
  end

  def handle_info(:playback_ready, socket) do
    {:noreply, update(socket, :playback, &Map.put(&1, :observed_state, :playing))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <main id="kino-theater" class="kino-shell">
        <section class="theater-panel">
          <header class="topbar">
            <strong>KINO</strong><span>│</span><span>theater</span>
            <span :if={@playback.title} class="now-title">{@playback.title}</span>
            <div class="provider-meta">
              <code :if={@playback.cache_key}>{@playback.cache_key}</code>
              <span :if={@playback.provider} class="provider">{@playback.provider}</span>
            </div>
          </header>

          <div class="screen">
            <div :if={@playback.observed_state == :idle} class="empty-state">
              <span>NO SOURCE</span><b>▷</b>
              <p>use <em>/play &lt;url&gt;</em> in chat to queue a video</p>
            </div>
            <div :if={@playback.observed_state == :buffering} class="empty-state buffering">
              <span>BUFFERING</span><b>◌</b><p>{@playback.title}</p>
            </div>
            <div :if={@playback.observed_state == :playing} class="playing-state">
              <div class="wave">波</div><p>{@playback.title}</p>
            </div>
          </div>

          <footer class="statebar">
            <span>desired: <i class={"dot #{@playback.desired_state}"}></i>{@playback.desired_state}</span>
            <b>→</b>
            <span>observed: <i class={"dot #{@playback.observed_state}"}></i>{@playback.observed_state}</span>
            <em :if={@playback.desired_state != @playback.observed_state}>state convergence pending</em>
            <small :if={@playback.requested_by}>req: {@playback.requested_by}</small>
          </footer>
        </section>

        <aside class="chat-panel">
          <header><span>CHAT</span><small><i class="online-dot"></i>4</small></header>
          <nav><span>natsuki</span><span>obata</span><span>reyna</span><strong>you</strong></nav>
          <div :if={@approval} class="approval-banner">◆ APPROVAL REQUIRED</div>

          <div id="messages" class="messages">
            <article
              :for={msg <- @messages}
              id={"message-#{msg.id}"}
              class={"message #{msg.type} #{msg.state}"}
            >
              <div class="message-head">
                <strong :if={msg.user}>{msg.user}</strong>
                <span :if={msg.type == :agent}>{state_icon(msg.state)} {msg.state}</span>
                <time>{msg.timestamp}</time>
              </div>
              <p>{msg.text}</p>
              <div :if={map_size(msg.payload) > 0} class="payload">
                <code :for={{key, value} <- msg.payload}>{key}: {value}</code>
              </div>
              <div :if={@approval && @approval.id == msg.id} class="approval-actions">
                <button id="approve-request" phx-click="approve">APPROVE</button>
                <button id="deny-request" phx-click="deny">DENY</button>
              </div>
            </article>
          </div>

          <.form for={@form} id="message-form" phx-submit="send" class="composer">
            <span>›</span>
            <input
              id="message-input"
              name="message"
              value={@form[:message].value}
              placeholder="message or /play <url>"
              autocomplete="off"
            />
          </.form>
          <footer>enter to send <span>/play /pause /queue /clear</span></footer>
        </aside>
      </main>
    </Layouts.app>
    """
  end

  defp state_icon(:pending), do: "○"
  defp state_icon(:working), do: "◌"
  defp state_icon(:success), do: "●"
  defp state_icon(:approval), do: "◆"
  defp state_icon(_state), do: "·"

  defp append_message(socket, message), do: update(socket, :messages, &(&1 ++ [message]))

  defp remove_message(socket, id),
    do: update(socket, :messages, &Enum.reject(&1, fn item -> item.id == id end))

  defp message(type, text, opts \\ []) do
    %{
      id: System.unique_integer([:positive]),
      type: type,
      timestamp: Time.utc_now() |> Time.truncate(:second) |> Time.to_string(),
      user: Keyword.get(opts, :user),
      text: text,
      state: Keyword.get(opts, :state),
      payload: Keyword.get(opts, :payload, %{})
    }
  end

  defp idle_playback do
    %{
      id: "idle",
      desired_state: :idle,
      observed_state: :idle,
      title: nil,
      requested_by: nil,
      duration: nil,
      cache_key: nil,
      provider: nil
    }
  end

  defp initial_messages do
    [
      message(:system, "kino session started — /play <url> to queue a video"),
      message(:user, "anyone got the new Tarkovsky restoration link?", user: "natsuki"),
      message(:user, "/play https://www.youtube.com/watch?v=dQw4w9WgXcQ", user: "obata"),
      message(:agent, "Resolving video metadata…",
        state: :pending,
        payload: %{url: "youtube:dQw4w9WgXcQ"}
      ),
      message(:agent, "Cache miss — enqueueing yt-dlp worker",
        state: :working,
        payload: %{job_id: "oban:2847", cache_key: "dQw4w9WgXcQ:1080p"}
      ),
      message(:user, "oh nice, seaweed bucket cache?", user: "reyna"),
      message(:agent, "Download complete — stored to kino-media cache",
        state: :success,
        payload: %{bytes: 148_897_792, duration: "3:32"}
      ),
      message(:agent, "Ready to play — awaiting host approval",
        state: :approval,
        payload: %{
          title: "Rick Astley — Never Gonna Give You Up",
          duration: "3:32",
          requested_by: "obata",
          cache_key: "dQw4w9WgXcQ:1080p"
        }
      )
    ]
  end
end
