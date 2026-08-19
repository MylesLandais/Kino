import {useEffect, useMemo, useState} from "react"
import {formatTime} from "tint/media"

import {AgentClient} from "./agent_client"
import {TheaterAvatar} from "./TheaterAvatar"
import {TheaterChat, useTheaterChatState} from "./TheaterChat"
import {TheaterPlayer} from "./TheaterPlayer"
import {TheaterSetlist} from "./TheaterSetlist"
import type {PlaybackState, TheaterSnapshot} from "./types"

const MODE_KEY = "kino:setlist-mode"

const defaultPlayback: PlaybackState = {
  chapters: [],
  revision: 0,
  position: 0,
}

export function TintTheaterApp() {
  const client = useMemo(() => new AgentClient(), [])
  const chat = useTheaterChatState()

  const [playback, setPlayback] = useState<PlaybackState>(defaultPlayback)
  const [reactions, setReactions] = useState<Record<number, string[]>>({})
  const [playCounts, setPlayCounts] = useState<Record<number, number>>({})
  const [setResolutions, setSetResolutions] = useState<TheaterSnapshot["set_resolutions"]>({})
  const [username, setUsername] = useState("")
  const [capabilities, setCapabilities] = useState<string[]>([])
  const [channelMode, setChannelMode] = useState("chat-only")
  const [tracklistOpen, setTracklistOpen] = useState(true)
  const [setlistMode, setSetlistMode] = useState<"overlay" | "push">(
    (window.localStorage.getItem(MODE_KEY) as "overlay" | "push") || "overlay",
  )
  const [expandedLinks, setExpandedLinks] = useState<Set<number>>(new Set())
  const [avatarProfile, setAvatarProfile] = useState<unknown>(null)
  const [avatarAnimation, setAvatarAnimation] = useState<unknown>(null)

  useEffect(() => {
    Object.assign(client.handlers, chat.chatHandlers, {
      onJoin: (resp: {username: string; capabilities: string[]; channel_mode: string}) => {
        chat.chatHandlers.onJoin(resp)
        setUsername(resp.username)
        setCapabilities(resp.capabilities)
        setChannelMode(resp.channel_mode)
      },
      onTheaterSnapshot: (next: TheaterSnapshot) => {
        setUsername(next.username)
        setCapabilities(next.capabilities)
        setChannelMode(next.channel_mode)
        setPlayback(next.playback)
        setReactions(next.reactions)
        setPlayCounts(next.play_counts)
        setSetResolutions(next.set_resolutions)
      },
      onTheaterPatch: (patch: Partial<TheaterSnapshot>) => {
        if (patch.reactions) setReactions(patch.reactions)
        if (patch.play_counts) setPlayCounts(patch.play_counts)
        if (patch.set_resolutions) setSetResolutions(patch.set_resolutions)
      },
      onPlaybackUpdated: (next: PlaybackState) => setPlayback(next),
      onAvatarProfile: setAvatarProfile,
      onAvatarAnimation: setAvatarAnimation,
      onChannelModeChanged: ({mode}: {mode: string}) => setChannelMode(mode),
    })
  }, [client, chat.chatHandlers])

  useEffect(() => {
    client.connect()
    return () => client.disconnect()
  }, [client])

  const modeItems = capabilities.length > 0 ? capabilities : ["chat-only"]

  return (
    <main id="kino-theater" className="flex h-dvh w-full overflow-hidden bg-tint-bg text-tint-ink">
      <section className="relative flex min-w-0 flex-1 flex-col border-r border-tint-border">
        <header className="flex min-h-10 shrink-0 items-center gap-3 border-b border-tint-border bg-tint-panel px-3 text-xs text-tint-muted">
          <strong className="text-tint-ink">KINO</strong>
          <span>│</span>
          <span>theater</span>
          {playback.title ? <span className="truncate text-tint-ink">{playback.title}</span> : null}
          {playback.cache_key ? (
            <div className="flex items-center gap-2 truncate">
              <code className="truncate">{playback.cache_key}</code>
              <span>{playback.provider || "media-cache"}</span>
            </div>
          ) : null}
          <div className="ml-auto flex gap-1">
            {modeItems.map((mode) => (
              <button
                key={mode}
                type="button"
                className={`rounded px-2 py-1 capitalize ${channelMode === mode ? "bg-tint-accent text-white" : "hover:bg-tint-accent-soft"}`}
                onClick={() => client.setChannelMode(mode)}
              >
                {mode}
              </button>
            ))}
          </div>
        </header>

        <div className={`relative flex min-h-0 flex-1 ${setlistMode === "push" ? "flex-row" : ""}`}>
          <TheaterSetlist
            playback={playback}
            reactions={reactions}
            playCounts={playCounts}
            setResolutions={setResolutions}
            username={username}
            open={tracklistOpen}
            mode={setlistMode}
            expandedLinks={expandedLinks}
            onToggleOpen={() => setTracklistOpen((open) => !open)}
            onSetMode={(mode) => {
              setSetlistMode(mode)
              window.localStorage.setItem(MODE_KEY, mode)
            }}
            onToggleLinks={(position) => {
              setExpandedLinks((prev) => {
                const next = new Set(prev)
                if (next.has(position)) next.delete(position)
                else next.add(position)
                return next
              })
            }}
            client={client}
          />

          <div className="relative flex min-w-0 flex-1 flex-col">
            <TheaterPlayer playback={playback} client={client} />
            {playback.cache_key ? <TheaterAvatar profile={avatarProfile} animation={avatarAnimation} /> : null}
          </div>
        </div>

        <footer className="flex shrink-0 flex-wrap items-center gap-3 border-t border-tint-border bg-tint-panel px-3 py-2 text-xs text-tint-muted">
          <span>desired: {playback.desired || "idle"}</span>
          <span>→</span>
          <span>observed: {playback.observed || "idle"}</span>
          {playback.source ? <span className="rounded bg-tint-surface px-2 py-0.5">{playback.source}</span> : null}
          {playback.desired !== playback.observed ? (
            <em className="text-tint-warning">state convergence pending</em>
          ) : null}
          <div className="ml-auto flex flex-wrap gap-3">
            {playback.requested_by ? (
              <small>
                req: <b>{playback.requested_by}</b>
              </small>
            ) : null}
            {playback.duration_seconds ? (
              <small>
                dur: <b>{formatTime(playback.duration_seconds)}</b>
              </small>
            ) : null}
            {playback.cache_key ? (
              <small>
                t: <b>{formatTime(playback.position)}</b>
              </small>
            ) : null}
          </div>
        </footer>
      </section>

      <aside className="flex w-[min(420px,38vw)] min-w-[280px] flex-col">
        <TheaterChat
          client={client}
          currentActorId={chat.currentActorId}
          messages={chat.messages}
          pipeline={chat.pipeline}
          composerState={chat.composerState}
          onComposerStateChange={chat.setComposerState}
        />
      </aside>
    </main>
  )
}
