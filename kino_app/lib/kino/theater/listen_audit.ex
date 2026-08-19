defmodule Kino.Theater.ListenAudit do
  @moduledoc """
  Tracks qualified listening progress for setlist play counts.

  State is kept per websocket client (listener id + playback session).
  """

  alias Kino.Media

  @type t :: %{
          listener_id: String.t(),
          playback_session_id: term(),
          last_position: float(),
          last_state: String.t(),
          accrued: %{optional(pos_integer()) => float()},
          recorded: MapSet.t()
        }

  @spec new(String.t(), term(), float(), String.t()) :: t()
  def new(listener_id, session_id, position, state) do
    %{
      listener_id: listener_id,
      playback_session_id: session_id,
      last_position: position,
      last_state: state,
      accrued: %{},
      recorded: MapSet.new()
    }
  end

  @spec advance(t(), map(), map(), String.t()) :: t()
  def advance(audit, playback, params, username) do
    listener_id = sanitize_listener_id(params["listener_id"])
    position = number(params["position"])
    state = params["state"]
    rate = max(number(params["playback_rate"] || 1), 0.25)
    discontinuity? = params["discontinuity"] == true

    audit =
      if audit.listener_id != listener_id or
           audit.playback_session_id != Map.get(playback, :playback_session_id) do
        new(listener_id, Map.get(playback, :playback_session_id), position, state)
      else
        audit
      end

    delta = position - audit.last_position
    credible? = audit.last_state == "playing" and delta > 0 and delta <= 15 * rate

    accrued =
      if credible? and not discontinuity? do
        allocate_progress(audit.accrued, playback, audit.last_position, position)
      else
        audit.accrued
      end

    recorded = qualify_entries(accrued, audit.recorded, playback, audit, username)

    %{
      audit
      | last_position: position,
        last_state: state,
        accrued: accrued,
        recorded: recorded
    }
  end

  defp allocate_progress(accrued, playback, from, to) do
    chapters = Map.get(playback, :chapters) || []

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

  defp qualify_entries(accrued, recorded, playback, audit, username) do
    media_id = Map.get(playback, :media_id)

    if is_nil(media_id) do
      recorded
    else
      chapters = Map.get(playback, :chapters) || []
      duration = Map.get(playback, :duration_seconds)
      session_id = Map.get(playback, :playback_session_id)

      Enum.reduce(chapters, recorded, fn entry, done ->
        position = entry["position"]
        listened = Map.get(accrued, position, 0.0)
        threshold = qualification_threshold(entry, duration)

        if listened >= threshold and not MapSet.member?(done, position) do
          asset = Media.get_asset!(media_id)

          Media.record_qualified_play(
            asset,
            entry,
            audit.listener_id,
            username,
            session_id,
            Float.round(listened, 2)
          )

          MapSet.put(done, position)
        else
          done
        end
      end)
    end
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
end
