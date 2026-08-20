import React, {useEffect, useRef} from "react"
import {formatTime} from "tint/media"

import type {AgentClient} from "./agent_client"
import type {ChapterEntry, PlaybackState, SetResolution} from "./types"

type Props = {
  playback: PlaybackState
  reactions: Record<number, string[]>
  playCounts: Record<number, number>
  setResolutions: Record<number, SetResolution>
  username: string
  open: boolean
  mode: "overlay" | "push"
  expandedLinks: Set<number>
  onToggleOpen: () => void
  onSetMode: (mode: "overlay" | "push") => void
  onToggleLinks: (position: number) => void
  client: AgentClient
}

function platformLabel(platform: string) {
  return platform.replace(/_/g, " ").toUpperCase()
}

function currentEntry(entry: ChapterEntry, position: number) {
  const start = entry.start_seconds || 0
  const stop = entry.end_seconds
  return position >= start && (stop == null || position < stop)
}

function playedEntry(entry: ChapterEntry, position: number) {
  const stop = entry.end_seconds
  return typeof stop === "number" && position >= stop
}

async function shareLink(url: string, title: string) {
  try {
    if (navigator.share) {
      await navigator.share({title, url})
    } else {
      await navigator.clipboard.writeText(url)
    }
  } catch (error: any) {
    if (error?.name !== "AbortError") {
      await navigator.clipboard.writeText(url)
    }
  }
}

export function TheaterSetlist({
  playback,
  reactions,
  playCounts,
  setResolutions,
  username,
  open,
  mode,
  expandedLinks,
  onToggleOpen,
  onSetMode,
  onToggleLinks,
  client,
}: Props) {
  const listRef = useRef<HTMLOListElement>(null)
  const chapters = playback.chapters || []

  useEffect(() => {
    if (!open) return
    const row = listRef.current?.querySelector('[data-current="true"]')
    if (!row || !listRef.current) return
    const list = listRef.current
    const listRect = list.getBoundingClientRect()
    const rowRect = row.getBoundingClientRect()
    const visible = rowRect.top >= listRect.top && rowRect.bottom <= listRect.bottom
    if (!visible) row.scrollIntoView({behavior: "smooth", block: "center"})
  }, [playback.position, open])

  if (chapters.length === 0) return null

  return (
    <>
      <div className="flex items-center gap-2 border-b border-tint-border px-3 py-2 text-xs text-tint-muted">
        <button
          type="button"
          className="rounded px-2 py-1 hover:bg-tint-accent-soft"
          onClick={onToggleOpen}
        >
          setlist {open ? "▾" : "▸"}
        </button>
        {open ? (
          <div className="flex gap-1">
            {(["overlay", "push"] as const).map((value) => (
              <button
                key={value}
                type="button"
                className={`rounded px-2 py-1 capitalize ${mode === value ? "bg-tint-accent text-white" : "hover:bg-tint-accent-soft"}`}
                onClick={() => onSetMode(value)}
              >
                {value}
              </button>
            ))}
          </div>
        ) : null}
      </div>

      {open ? (
        <aside
          className={
            mode === "overlay"
              ? "absolute inset-y-0 left-0 z-20 w-72 border-r border-tint-border bg-tint-panel/95 backdrop-blur"
              : "w-72 shrink-0 border-r border-tint-border bg-tint-panel"
          }
        >
          <div className="grid grid-cols-[2rem_1fr_auto] gap-2 border-b border-tint-border px-3 py-2 text-[0.65rem] uppercase tracking-wide text-tint-muted">
            <span>#</span>
            <span>Track</span>
            <span>Time</span>
          </div>
          <ol ref={listRef} className="max-h-full overflow-y-auto py-1">
            {chapters.map((entry) => {
              const position = entry.position
              const resolution = setResolutions[position]
              const isCurrent = currentEntry(entry, playback.position)
              const isPlayed = playedEntry(entry, playback.position)
              const liked = (reactions[position] || []).includes(username)
              const expanded = expandedLinks.has(position)

              return (
                <li
                  key={position}
                  data-current={isCurrent || undefined}
                  className={`border-b border-tint-border/50 px-3 py-2 text-sm ${isCurrent ? "bg-tint-accent-soft" : ""} ${isPlayed ? "opacity-60" : ""}`}
                >
                  <div
                    className="grid cursor-pointer grid-cols-[2rem_1fr_auto] items-start gap-2"
                    onClick={() => {
                      const video = document.querySelector("#tint-theater video") as HTMLVideoElement | null
                      if (video) video.currentTime = Number(entry.start_seconds) || 0
                    }}
                  >
                    <span className="text-tint-muted">{isCurrent ? "♫" : position}</span>
                    <span>
                      {entry.artist ? <strong className="mr-1">{entry.artist}</strong> : null}
                      <em>{entry.title || entry.label}</em>
                    </span>
                    <time className="text-xs text-tint-muted">{formatTime(entry.start_seconds || 0)}</time>
                  </div>
                  <div className="mt-2 flex flex-wrap items-center gap-2 text-xs">
                    <button
                      type="button"
                      className={`rounded px-2 py-0.5 ${liked ? "text-tint-danger" : "text-tint-muted hover:bg-tint-surface"}`}
                      onClick={(event) => {
                        event.stopPropagation()
                        client.toggleLike(position)
                      }}
                    >
                      ♥ {(reactions[position] || []).length || ""}
                    </button>
                    {resolution ? (
                      <button
                        type="button"
                        className="rounded px-2 py-0.5 text-tint-link hover:bg-tint-surface"
                        onClick={(event) => {
                          event.stopPropagation()
                          onToggleLinks(position)
                        }}
                      >
                        links {resolution.links.length}
                      </button>
                    ) : null}
                    {(playCounts[position] || 0) > 0 ? (
                      <small className="text-tint-muted">▷{playCounts[position]}</small>
                    ) : null}
                  </div>
                  {resolution && expanded ? (
                    <div className="mt-2 rounded border border-tint-border bg-tint-surface p-2 text-xs">
                      <header className="mb-1 flex justify-between text-tint-muted">
                        <span>Available on</span>
                        <small>verified ≥80%</small>
                      </header>
                      {resolution.links.length === 0 ? (
                        <p className="text-tint-muted">{resolution.resolution.status}…</p>
                      ) : (
                        resolution.links.map((link) => (
                          <div key={link.url} className="mt-1 flex items-center justify-between gap-2">
                            <a
                              href={link.url}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="text-tint-link hover:underline"
                            >
                              <strong>{platformLabel(link.platform)}</strong>{" "}
                              {Math.round(link.confidence * 100)}% ↗
                            </a>
                            <button
                              type="button"
                              className="rounded px-2 py-0.5 hover:bg-tint-panel"
                              onClick={() =>
                                shareLink(link.url, `${entry.artist} — ${entry.title || entry.label}`)
                              }
                            >
                              share
                            </button>
                          </div>
                        ))
                      )}
                    </div>
                  ) : null}
                </li>
              )
            })}
            <li className="px-3 py-2 text-xs text-tint-muted">end of set</li>
          </ol>
        </aside>
      ) : null}
    </>
  )
}
