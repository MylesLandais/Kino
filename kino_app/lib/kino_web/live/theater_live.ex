defmodule KinoWeb.TheaterLive do
  use KinoWeb, :live_view

  alias Kino.Media
  alias Kino.Media.LinkResolver
  alias Kino.Media.SetBroker
  alias Kino.Theater.RoomSession

  # Keep only the most recent messages in the stream (negative = keep tail).
  @message_limit -200

  @impl true
  def mount(_params, session, socket) do
    user = Kino.Accounts.user_for_session(session["auth_token"])
    username = user && user.username

    if is_nil(username) do
      {:ok, assign(socket, page_title: "Join", username: nil, current_scope: nil)}
    else
      mount_theater(username, user, socket)
    end
  end

  defp mount_theater(username, user, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Kino.PubSub, Media.topic())
    end

    socket =
      socket
      |> assign(:page_title, "Theater")
      |> assign(:username, username)
      |> assign(:current_scope, %{user: user})
      |> assign(:form, to_form(%{"message" => ""}))
      |> assign(:command_hint, nil)
      |> assign(:pipeline, nil)
      |> assign(:tracklist_open, true)
      |> assign(:setlist_mode, "overlay")
      |> assign(:listen_audit, nil)
      |> assign(:reactions, %{})
      |> assign(:play_counts, %{})
      |> assign(:set_resolutions, %{})
      |> assign(:expanded_track_links, MapSet.new())
      |> stream(
        :messages,
        [message(:system, "kino session started — /play <url> to queue a video")],
        limit: @message_limit
      )
      |> assign_playback(RoomSession.current())

    {:ok, socket |> push_playback() |> push_avatar_profile()}
  end

  @impl true
  def handle_event("avatar_profile_request", _params, socket) do
    {:reply, Kino.Avatar.profile_payload(), socket}
  end

  def handle_event("playback_request", _params, socket) do
    {:reply, playback_payload(socket.assigns.playback), socket}
  end

  def handle_event("send", %{"message" => text}, socket) do
    text = String.trim(text)

    socket =
      socket
      |> assign(:form, to_form(%{"message" => ""}))
      |> assign(:command_hint, nil)

    cond do
      text == "" ->
        {:noreply, socket}

      String.starts_with?(text, "/play ") ->
        url = text |> String.trim_leading("/play ") |> String.trim()
        Media.broadcast({:chat_message, message(:user, text, user: socket.assigns.username)})

        case Media.request_play(url, socket.assigns.username) do
          {:ok, _asset} ->
            {:noreply, socket}

          {:error, reason} ->
            reason = if is_binary(reason), do: reason, else: inspect(reason)

            Media.broadcast_agent(:error, "Could not queue request — #{reason}", %{
              url: url
            })

            {:noreply, socket}
        end

      String.starts_with?(text, "/wish ") ->
        query = text |> String.trim_leading("/wish ") |> String.trim()
        Media.broadcast({:chat_message, message(:user, text, user: socket.assigns.username)})

        case LinkResolver.parse_query(query) do
          {:ok, recording} ->
            Media.broadcast_agent(:working, "Searching seven music platforms…", %{
              artist: recording.artist,
              title: recording.title,
              threshold: "80%"
            })

            Task.Supervisor.start_child(Kino.TaskSupervisor, fn -> resolve_wish(query) end)
            {:noreply, socket}

          {:error, reason} ->
            Media.broadcast_agent(:error, reason)
            {:noreply, socket}
        end

      text == "/pause" ->
        RoomSession.set_desired(:paused)
        {:noreply, socket}

      text == "/resume" ->
        RoomSession.set_desired(:playing)
        {:noreply, socket}

      true ->
        Media.broadcast({:chat_message, message(:user, text, user: socket.assigns.username)})

        if Kino.Accounts.allowed?(socket.assigns.current_scope.user, "avatar:trigger") do
          if asset = Kino.Avatar.match_motion(text), do: Kino.Avatar.trigger(asset)
        end

        {:noreply, socket}
    end
  end

  def handle_event("command_changed", %{"message" => text}, socket) do
    hint =
      cond do
        String.starts_with?(text, "/play") -> "/play <video-url> — fetch and cache with yt-dlp"
        String.starts_with?(text, "/wish") -> "/wish Artist — Track — resolve ≥80% platform links"
        String.starts_with?(text, "/") -> "command: #{text}"
        true -> nil
      end

    {:noreply,
     socket
     |> assign(:form, to_form(%{"message" => text}))
     |> assign(:command_hint, hint)}
  end

  def handle_event(
        "observed_playback",
        %{"state" => state, "position" => position} = params,
        socket
      )
      when state in ~w(playing paused buffering error) do
    RoomSession.report_observed(String.to_existing_atom(state), position)
    {:noreply, audit_playback_sample(socket, params)}
  end

  def handle_event("playback_intent", %{"desired" => desired}, socket)
      when desired in ~w(playing paused) do
    RoomSession.set_desired(String.to_existing_atom(desired))
    {:noreply, socket}
  end

  def handle_event("toggle_tracklist", _params, socket) do
    {:noreply, assign(socket, :tracklist_open, !socket.assigns.tracklist_open)}
  end

  def handle_event("set_setlist_mode", %{"mode" => mode}, socket)
      when mode in ~w(overlay push) do
    {:noreply,
     socket
     |> assign(:setlist_mode, mode)
     |> push_event("setlist_preference", %{mode: mode})}
  end

  def handle_event("seek", %{"position" => position}, socket) do
    {:noreply, push_event(socket, "seek", %{position: position})}
  end

  def handle_event("toggle_like", %{"position" => position}, socket) do
    if media_id = socket.assigns.playback.media_id do
      Media.toggle_reaction(media_id, String.to_integer(position), socket.assigns.username)
    end

    {:noreply, socket}
  end

  def handle_event("toggle_track_links", %{"position" => position}, socket) do
    position = String.to_integer(position)
    expanded = socket.assigns.expanded_track_links

    expanded =
      if MapSet.member?(expanded, position),
        do: MapSet.delete(expanded, position),
        else: MapSet.put(expanded, position)

    {:noreply, assign(socket, :expanded_track_links, expanded)}
  end

  def handle_event("share_track_link", %{"url" => url, "title" => title}, socket) do
    {:noreply, push_event(socket, "share-track-link", %{url: url, title: title})}
  end

  def handle_event("ignore_track_click", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:chat_message, msg}, socket) do
    {:noreply, append_message(socket, msg)}
  end

  def handle_info({:agent_event, %{state: state, text: text, payload: payload}}, socket) do
    {:noreply,
     socket
     |> assign(:pipeline, pipeline_from_agent(state, text, socket.assigns.pipeline))
     |> append_message(message(:agent, text, state: state, payload: payload))}
  end

  def handle_info({:pipeline_progress, progress}, socket) do
    pipeline = %{
      stage: "caching",
      text: "caching full quality",
      percent: progress.percent,
      speed: progress[:speed],
      eta: progress[:eta]
    }

    {:noreply, assign(socket, :pipeline, pipeline)}
  end

  def handle_info({:reactions_updated, asset_id}, socket) do
    if socket.assigns.playback.media_id == asset_id do
      {:noreply, assign(socket, :reactions, Media.reactions_for(asset_id))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:plays_updated, asset_id}, socket) do
    if socket.assigns.playback.media_id == asset_id do
      asset = Media.get_asset!(asset_id)
      {:noreply, assign(socket, :play_counts, Media.play_counts_for(asset))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:set_enrichment_updated, asset_id}, socket) do
    if socket.assigns.playback.media_id == asset_id do
      {:noreply, assign(socket, :set_resolutions, SetBroker.resolutions_for_asset(asset_id))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:playback_updated, state}, socket) do
    {:noreply, socket |> assign_playback(state) |> push_playback()}
  end

  def handle_info({:avatar_animation, payload}, socket),
    do: {:noreply, push_event(socket, "avatar_animation", payload)}

  def handle_info({:avatar_profile_updated, _key}, socket),
    do: {:noreply, push_avatar_profile(socket)}

  def handle_info({:avatar_catalog_updated, _id}, socket), do: {:noreply, socket}

  @impl true
  def render(%{username: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="kino-shell join-shell">
        <form action="/session" method="post" class="join-card" id="join-form">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <strong>KINO</strong>
          <p>pick a handle to enter the theater</p>
          <input
            name="username"
            placeholder="handle"
            autocomplete="off"
            autofocus
            minlength="2"
            maxlength="24"
            pattern="[a-zA-Z0-9_\-]+"
            required
          />
          <button type="submit">enter ›</button>
        </form>
      </main>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main id="kino-theater" class="kino-shell" phx-hook="TheaterPreferences">
        <section class="theater-panel">
          <header class="topbar">
            <strong>KINO</strong><span>│</span><span>theater</span>
            <button
              :if={@playback.chapters != []}
              id="setlist-toggle"
              class={"setlist-toggle #{if @tracklist_open, do: "open"}"}
              phx-click="toggle_tracklist"
            >
              setlist
            </button>
            <div :if={@playback.chapters != []} class="setlist-mode" aria-label="Setlist layout">
              <button
                id="setlist-mode-overlay"
                type="button"
                class={[@setlist_mode == "overlay" && "active"]}
                phx-click="set_setlist_mode"
                phx-value-mode="overlay"
                aria-pressed={@setlist_mode == "overlay"}
              >
                overlay
              </button>
              <button
                id="setlist-mode-push"
                type="button"
                class={[@setlist_mode == "push" && "active"]}
                phx-click="set_setlist_mode"
                phx-value-mode="push"
                aria-pressed={@setlist_mode == "push"}
              >
                push
              </button>
            </div>
            <span :if={@playback.title} class="now-title">{@playback.title}</span>
            <div class="provider-meta">
              <code :if={@playback.cache_key}>{@playback.cache_key}</code>
              <span :if={@playback.cache_key} class="provider">
                {@playback.provider || "media-cache"}
              </span>
            </div>
          </header>

          <div class={["theater-body", "setlist-#{@setlist_mode}"]}>
            <aside :if={@tracklist_open && @playback.chapters != []} id="setlist" class="setlist-col">
              <div class="setlist-head">
                <span>#</span><span class="col-track">Track</span><span>Time</span>
              </div>
              <ol id="setlist-rows" phx-hook="SetList">
                <li
                  :for={entry <- @playback.chapters}
                  id={"setlist-track-#{entry["position"]}"}
                  class={[
                    "track",
                    current_entry?(entry, @playback.position) && "current",
                    played?(entry, @playback.position) && "played",
                    MapSet.member?(@expanded_track_links, entry["position"]) && "expanded"
                  ]}
                  phx-click="seek"
                  phx-value-position={entry["start_seconds"]}
                >
                  <div class="track-main">
                    <span class="track-num">
                      <span :if={!current_entry?(entry, @playback.position)}>
                        {entry["position"]}
                      </span>
                      <span
                        :if={current_entry?(entry, @playback.position)}
                        class="eq"
                        aria-hidden="true"
                      >
                        <i style="height:50%;animation-duration:.38s"></i>
                        <i style="height:100%;animation-duration:.49s"></i>
                        <i style="height:65%;animation-duration:.6s"></i>
                        <i style="height:85%;animation-duration:.71s"></i>
                        <i style="height:45%;animation-duration:.82s"></i>
                      </span>
                    </span>
                    <span class="track-label">
                      <strong :if={entry["artist"]}>{entry["artist"]}</strong>
                      <em>{entry["title"] || entry["label"]}</em>
                    </span>
                  </div>
                  <button
                    id={"setlist-like-#{entry["position"]}"}
                    type="button"
                    class={"track-like #{if @username in Map.get(@reactions, entry["position"], []), do: "liked"}"}
                    phx-click="toggle_like"
                    phx-value-position={entry["position"]}
                    aria-label={"Heart #{entry["title"] || entry["label"]}"}
                    title="Heart track"
                  >
                    ♥<small :if={Map.get(@reactions, entry["position"], []) != []}>{length(
                      @reactions[entry["position"]]
                    )}</small>
                  </button>
                  <div class="track-stats">
                    <% resolution = Map.get(@set_resolutions, entry["position"]) %>
                    <button
                      :if={resolution}
                      id={"setlist-links-#{entry["position"]}"}
                      type="button"
                      class={[
                        "track-links-toggle",
                        resolution.links != [] && "resolved",
                        resolution.resolution.status == "resolving" && "working"
                      ]}
                      phx-click="toggle_track_links"
                      phx-value-position={entry["position"]}
                      aria-expanded={MapSet.member?(@expanded_track_links, entry["position"])}
                      title="Platform links"
                    >
                      <span aria-hidden="true" class="track-links-chevron">›</span>
                      <span>links</span>
                      <b>{length(resolution.links)}</b>
                    </button>
                    <small
                      :if={Map.get(@play_counts, entry["position"], 0) > 0}
                      class="track-plays"
                      title="Qualified plays"
                    >
                      ▷{Map.get(@play_counts, entry["position"], 0)}
                    </small>
                    <time class="track-time">{format_time(entry["start_seconds"])}</time>
                  </div>
                  <div
                    :if={resolution && MapSet.member?(@expanded_track_links, entry["position"])}
                    id={"setlist-link-panel-#{entry["position"]}"}
                    class="track-link-panel"
                    phx-click="ignore_track_click"
                  >
                    <header>
                      <span>Available on</span>
                      <small>verified ≥80%</small>
                    </header>
                    <p :if={resolution.links == [] && resolution.resolution.status == "resolving"}>
                      checking ontology + providers…
                    </p>
                    <p :if={resolution.links == [] && resolution.resolution.status == "unresolved"}>
                      unresolved — waiting for stronger artist/title evidence
                    </p>
                    <p :if={resolution.links == [] && resolution.resolution.status == "enriched"}>
                      no platform links met 80% confidence
                    </p>
                    <div
                      :for={link <- resolution.links}
                      class="track-link-row"
                    >
                      <a href={link.url} target="_blank" rel="noopener noreferrer">
                        <strong>{platform_label(link.platform)}</strong>
                        <span>{round(link.confidence * 100)}% ↗</span>
                      </a>
                      <button
                        type="button"
                        phx-click="share_track_link"
                        phx-value-url={link.url}
                        phx-value-title={"#{entry["artist"]} — #{entry["title"] || entry["label"]}"}
                        title="Share or copy link"
                        aria-label={"Share #{platform_label(link.platform)} link"}
                      >
                        share
                      </button>
                    </div>
                  </div>
                </li>
                <li class="end-cap">end of set</li>
              </ol>
            </aside>

            <div class="screen">
              <div :if={is_nil(@playback.cache_key)} class="empty-state">
                <span>NO SOURCE</span><b>▷</b>
                <p>use <em>/play &lt;url&gt;</em> in chat to queue a video</p>
              </div>
              <div
                :if={@playback.cache_key}
                id="theater-video-wrap"
                class="theater-video-wrap"
                phx-hook="VideoPlayer"
                phx-update="ignore"
              >
                <video id="theater-video" class="theater-video" playsinline></video>
                <div
                  id="theater-avatar"
                  class="theater-avatar"
                  phx-hook="AvatarRenderer"
                  phx-update="ignore"
                  aria-hidden="true"
                >
                  <canvas id="theater-avatar-canvas"></canvas>
                  <span class="avatar-loading">loading avatar…</span>
                </div>
              </div>
              <div
                :if={@playback.cache_key && @playback.observed == :buffering}
                id="buffering-state"
                class="screen-state buffering-state"
              >
                <span>BUFFERING</span>
                <div class="buffer-bars" aria-hidden="true"><i></i><i></i><i></i><i></i></div>
                <p>{@playback.title}</p>
              </div>
              <div
                :if={@playback.cache_key && @playback.observed == :error}
                id="playback-error-state"
                class="screen-state error-state"
              >
                <span>PLAYBACK ERROR</span><b>×</b>
                <p>Use the player controls or queue another source.</p>
              </div>
            </div>
          </div>

          <footer class="statebar">
            <span>desired: <i class={"dot #{@playback.desired}"}></i>{@playback.desired}</span>
            <b>→</b>
            <span>observed: <i class={"dot #{@playback.observed}"}></i>{@playback.observed}</span>
            <span :if={@playback.source} class={"source-chip #{@playback.source}"}>
              {@playback.source}
            </span>
            <em :if={@playback.desired != @playback.observed}>state convergence pending</em>
            <div class="playback-meta">
              <small :if={@playback.requested_by}>req: <b>{@playback.requested_by}</b></small>
              <small :if={@playback.duration_seconds}>
                dur: <b>{format_time(@playback.duration_seconds)}</b>
              </small>
              <small :if={@playback.cache_key}>t: <b>{format_time(@playback.position)}</b></small>
            </div>
          </footer>
        </section>

        <aside class="chat-panel">
          <header><span>CHAT</span><small><i class="online-dot"></i>1</small></header>
          <nav><strong>{@username}</strong></nav>

          <div :if={@pipeline} id="pipeline-card" class="pipeline-card">
            <div class="pipeline-head">
              <span class="pipeline-stage">{@pipeline.stage}</span>
              <small :if={@pipeline[:speed]}>{@pipeline[:speed]} · ETA {@pipeline[:eta]}</small>
            </div>
            <p>{@pipeline[:text]}</p>
            <div :if={@pipeline[:percent]} class="pipeline-bar">
              <i style={"width: #{@pipeline.percent}%"}></i>
            </div>
          </div>

          <div id="messages" class="messages" phx-update="stream" phx-hook="MessageList">
            <article
              :for={{id, msg} <- @streams.messages}
              id={id}
              class={"msg #{msg.type} #{msg.state} #{if msg.user == @username, do: "own"}"}
            >
              <p :if={msg.type == :system} class="msg-pill">{msg.text}</p>
              <%= if msg.type != :system do %>
                <div :if={msg.type == :agent} class="msg-meta">
                  <span class={"agent-state #{msg.state}"}>
                    {state_icon(msg.state)} kino-agent · {msg.state}
                  </span>
                </div>
                <div :if={msg.type == :user && msg.user != @username} class="msg-meta">
                  <span class="msg-author">{msg.user}</span>
                </div>
                <div class="bubble">
                  <p>{msg.text}</p>
                  <div :if={map_size(msg.payload) > 0} class="payload">
                    <code :for={{key, value} <- msg.payload}>{key}: {value}</code>
                  </div>
                  <time>{msg.timestamp}</time>
                </div>
              <% end %>
            </article>
          </div>

          <div :if={@command_hint} id="command-hint" class="command-hint">{@command_hint}</div>

          <.form
            for={@form}
            id="message-form"
            phx-change="command_changed"
            phx-submit="send"
            class="composer-wrap"
          >
            <div class="composer">
              <span>›</span>
              <input
                id="message-input"
                name="message"
                value={@form[:message].value}
                placeholder="message or /play <url>"
                autocomplete="off"
              />
            </div>
            <footer>enter to send <span>/play /wish /pause /resume</span></footer>
          </.form>
        </aside>
      </main>
    </Layouts.app>
    """
  end

  defp assign_playback(socket, %RoomSession{} = state) do
    previous = socket.assigns[:playback]
    socket = assign(socket, :playback, state)

    if state.media_id && (is_nil(previous) || previous.media_id != state.media_id) do
      asset = Media.get_asset(state.media_id)

      socket
      |> assign(:reactions, Media.reactions_for(state.media_id))
      |> assign(:play_counts, if(asset, do: Media.play_counts_for(asset), else: %{}))
      |> assign(:set_resolutions, SetBroker.resolutions_for_asset(state.media_id))
      |> assign(:listen_audit, nil)
    else
      socket
    end
  end

  defp resolve_wish(query) do
    case SetBroker.resolve_query(query) do
      {:ok, %{recording: recording, matches: []}} ->
        Media.broadcast_agent(
          :error,
          "No platform returned an 80% match for #{recording.artist} — #{recording.title}."
        )

      {:ok, %{recording: recording, matches: matches}} ->
        links =
          matches
          |> Enum.sort_by(&to_string(&1.platform))
          |> Enum.map_join("\n", fn match ->
            confidence = round(match.confidence * 100)
            "#{platform_label(match.platform)} #{confidence}% — #{match.url}"
          end)

        Media.broadcast_agent(
          :success,
          "Links for #{recording.artist} — #{recording.title}:\n#{links}",
          %{matched: length(matches), checked: length(LinkResolver.providers())}
        )

      {:error, reason} ->
        Media.broadcast_agent(:error, reason)
    end
  rescue
    error -> Media.broadcast_agent(:error, "Platform lookup failed — #{Exception.message(error)}")
  end

  defp platform_label(platform) do
    platform
    |> to_string()
    |> String.replace("_", " ")
    |> String.upcase()
  end

  defp push_playback(%{assigns: %{playback: %{src: nil}}} = socket), do: socket

  defp push_playback(socket) do
    push_event(socket, "playback", playback_payload(socket.assigns.playback))
  end

  defp playback_payload(pb) do
    %{
      src: pb.src,
      source: pb.source,
      desired: pb.desired,
      revision: pb.revision,
      position: pb.position,
      playback_session_id: pb.playback_session_id,
      markers:
        Enum.map(pb.chapters || [], fn ch ->
          %{time: ch["start_seconds"], label: ch["label"]}
        end)
    }
  end

  defp push_avatar_profile(socket) do
    if connected?(socket),
      do: push_event(socket, "avatar_profile", Kino.Avatar.profile_payload()),
      else: socket
  end

  defp pipeline_from_agent(:pending, text, _prev),
    do: %{stage: "resolving", text: text, percent: nil}

  defp pipeline_from_agent(:working, text, prev),
    do: %{stage: "working", text: text, percent: prev[:percent]}

  defp pipeline_from_agent(_success_or_error, _text, _prev), do: nil

  defp current_entry?(entry, position) do
    start = entry["start_seconds"] || 0
    stop = entry["end_seconds"]
    position >= start and (is_nil(stop) or position < stop)
  end

  defp played?(entry, position) do
    stop = entry["end_seconds"]
    is_number(stop) and position >= stop
  end

  defp audit_playback_sample(%{assigns: %{playback: %{media_id: nil}}} = socket, _params),
    do: socket

  defp audit_playback_sample(socket, params) do
    playback = socket.assigns.playback
    listener_id = sanitize_listener_id(params["listener_id"])
    position = number(params["position"])
    state = params["state"]
    rate = max(number(params["playback_rate"] || 1), 0.25)
    discontinuity? = params["discontinuity"] == true
    previous = socket.assigns.listen_audit

    audit =
      if is_nil(previous) or previous.listener_id != listener_id or
           previous.playback_session_id != playback.playback_session_id do
        new_audit(listener_id, playback.playback_session_id, position, state)
      else
        advance_audit(previous, playback, position, state, rate, discontinuity?, socket)
      end

    assign(socket, :listen_audit, audit)
  end

  defp new_audit(listener_id, session_id, position, state) do
    %{
      listener_id: listener_id,
      playback_session_id: session_id,
      last_position: position,
      last_state: state,
      accrued: %{},
      recorded: MapSet.new()
    }
  end

  defp advance_audit(audit, playback, position, state, rate, discontinuity?, socket) do
    delta = position - audit.last_position
    credible? = audit.last_state == "playing" and delta > 0 and delta <= 15 * rate

    accrued =
      if credible? and not discontinuity? do
        allocate_progress(audit.accrued, playback.chapters, audit.last_position, position)
      else
        audit.accrued
      end

    recorded = qualify_entries(accrued, audit.recorded, playback, audit, socket)
    %{audit | last_position: position, last_state: state, accrued: accrued, recorded: recorded}
  end

  defp allocate_progress(accrued, chapters, from, to) do
    Enum.reduce(chapters, accrued, fn entry, totals ->
      start = number(entry["start_seconds"])
      stop = number(entry["end_seconds"] || to)
      listened = max(min(to, stop) - max(from, start), 0.0)

      if listened > 0 do
        Map.update(totals, entry["position"], listened, &(&1 + listened))
      else
        totals
      end
    end)
  end

  defp qualify_entries(accrued, recorded, playback, audit, socket) do
    Enum.reduce(playback.chapters, recorded, fn entry, done ->
      position = entry["position"]
      listened = Map.get(accrued, position, 0.0)
      threshold = qualification_threshold(entry, playback.duration_seconds)

      if listened >= threshold and not MapSet.member?(done, position) do
        asset = Media.get_asset!(playback.media_id)

        Media.record_qualified_play(
          asset,
          entry,
          audit.listener_id,
          socket.assigns.username,
          playback.playback_session_id,
          Float.round(listened, 2)
        )

        MapSet.put(done, position)
      else
        done
      end
    end)
  end

  defp qualification_threshold(entry, duration) do
    start = number(entry["start_seconds"])
    stop = number(entry["end_seconds"] || duration || start + 60)
    min(30.0, max((stop - start) / 2, 1.0))
  end

  defp sanitize_listener_id(id) when is_binary(id) do
    id |> String.replace(~r/[^a-zA-Z0-9_-]/, "") |> String.slice(0, 64)
  end

  defp sanitize_listener_id(_), do: "anonymous"

  defp number(value) when is_number(value), do: value * 1.0

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> 0.0
    end
  end

  defp number(_), do: 0.0

  defp state_icon(:pending), do: "○"
  defp state_icon(:working), do: "◌"
  defp state_icon(:success), do: "●"
  defp state_icon(:error), do: "✗"
  defp state_icon(_state), do: "·"

  defp append_message(socket, message),
    do: stream_insert(socket, :messages, message, limit: @message_limit)

  defp format_time(nil), do: "0:00"

  defp format_time(seconds) do
    seconds = seconds |> trunc() |> max(0)
    hours = div(seconds, 3600)
    minutes = seconds |> rem(3600) |> div(60)
    remaining = rem(seconds, 60)

    if hours > 0 do
      "#{hours}:#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(remaining), 2, "0")}"
    else
      "#{minutes}:#{String.pad_leading(Integer.to_string(remaining), 2, "0")}"
    end
  end

  defp message(type, text, opts \\ []) do
    %{
      id: System.unique_integer([:positive]),
      type: type,
      timestamp: Calendar.strftime(Time.utc_now(), "%H:%M"),
      user: Keyword.get(opts, :user),
      text: text,
      state: Keyword.get(opts, :state),
      payload: Keyword.get(opts, :payload, %{})
    }
  end
end
