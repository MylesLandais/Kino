import {useEffect, useRef, useState} from "react"
import {VideoPlayer} from "tint/video-player"

import type {AgentClient} from "./agent_client"
import {getListenerId} from "./agent_client"
import type {PlaybackState} from "./types"

type Props = {
  playback: PlaybackState
  client: AgentClient
}

const STATE_MAP: Record<string, string> = {
  playing: "playing",
  pause: "paused",
  waiting: "buffering",
  error: "error",
  ended: "paused",
}

export function TheaterPlayer({playback, client}: Props) {
  const wrapRef = useRef<HTMLDivElement>(null)
  const revisionRef = useRef<number | null>(null)
  const loadedSrcRef = useRef<string | null>(null)
  const commandedDesiredRef = useRef<string | null>(null)
  const desiredRef = useRef<string>("idle")
  const seekingRef = useRef(false)
  const resumeAfterSeekRef = useRef(false)
  const [videoSrc, setVideoSrc] = useState<string | null>(playback.src || null)

  const report = (state: string, discontinuity = false) => {
    const video = wrapRef.current?.querySelector("video")
    client.observedPlayback({
      state,
      position: video?.currentTime || 0,
      playback_rate: video?.playbackRate || 1,
      listener_id: getListenerId(),
      discontinuity,
    })
  }

  useEffect(() => {
    if (!playback.src) return

    const desiredChanged = desiredRef.current !== playback.desired
    desiredRef.current = playback.desired || "idle"

    const srcChanged = loadedSrcRef.current !== playback.src
    if (revisionRef.current !== playback.revision && srcChanged) {
      const video = wrapRef.current?.querySelector("video")
      const resumeAt = loadedSrcRef.current && video ? video.currentTime : 0
      loadedSrcRef.current = playback.src
      setVideoSrc(playback.src)

      const target = Math.max(Number(playback.position) || 0, resumeAt)
      if (target > 0) {
        window.setTimeout(() => {
          const el = wrapRef.current?.querySelector("video")
          if (el) el.currentTime = target
        }, 100)
      }
    }

    revisionRef.current = playback.revision

    const video = wrapRef.current?.querySelector("video")
    if (!video) return

    if (playback.desired === "playing" && (desiredChanged || srcChanged)) {
      commandedDesiredRef.current = "playing"
      Promise.resolve(video.play())
        .catch(() => report("paused"))
        .finally(() => {
          commandedDesiredRef.current = null
        })
    } else if (playback.desired === "paused" && desiredChanged) {
      commandedDesiredRef.current = "paused"
      video.pause()
      commandedDesiredRef.current = null
    }
  }, [playback, client])

  useEffect(() => {
    const wrap = wrapRef.current
    if (!wrap) return

    const video = wrap.querySelector("video")
    if (!video) return

    const listeners = Object.keys(STATE_MAP).map((ev) => {
      const fn = () => {
        const state = STATE_MAP[ev]
        const commanded = commandedDesiredRef.current === state
        if (ev === "pause" && seekingRef.current && resumeAfterSeekRef.current) return
        if (ev === "playing" && !commanded) {
          desiredRef.current = "playing"
          client.playbackIntent("playing")
        }
        if ((ev === "pause" || ev === "ended") && !commanded) {
          desiredRef.current = "paused"
          client.playbackIntent("paused")
        }
        report(state)
      }
      video.addEventListener(ev, fn)
      return () => video.removeEventListener(ev, fn)
    })

    const onSeeking = () => {
      if (seekingRef.current) return
      seekingRef.current = true
      resumeAfterSeekRef.current = desiredRef.current === "playing" || !video.paused
    }

    const onSeeked = () => {
      const shouldResume = resumeAfterSeekRef.current
      seekingRef.current = false
      resumeAfterSeekRef.current = false
      report(video.paused ? "paused" : "playing", true)

      if (shouldResume && video.paused) {
        commandedDesiredRef.current = "playing"
        Promise.resolve(video.play())
          .catch(() => report("paused"))
          .finally(() => {
            commandedDesiredRef.current = null
          })
      }
    }

    video.addEventListener("seeking", onSeeking)
    video.addEventListener("seeked", onSeeked)

    const timer = window.setInterval(() => {
      if (!video.paused && !video.ended) report("playing")
    }, 5000)

    return () => {
      listeners.forEach((off) => off())
      video.removeEventListener("seeking", onSeeking)
      video.removeEventListener("seeked", onSeeked)
      window.clearInterval(timer)
    }
  }, [videoSrc, client])

  if (!playback.cache_key || !videoSrc) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center gap-3 text-tint-muted">
        <span className="text-xs tracking-[0.2em]">NO SOURCE</span>
        <span className="text-3xl text-tint-accent">▷</span>
        <p className="text-sm">
          use <em>/play &lt;url&gt;</em> in chat to queue a video
        </p>
      </div>
    )
  }

  return (
    <div ref={wrapRef} className="relative flex min-h-0 flex-1 flex-col">
      <VideoPlayer
        src={videoSrc}
        label={playback.title || "Theater video"}
        title={playback.title || undefined}
        duration={playback.duration_seconds || undefined}
        autoHideControls
        className="min-h-0 flex-1"
      />
      {playback.observed === "buffering" ? (
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center bg-tint-bg/70">
          <span className="text-xs tracking-[0.2em] text-tint-warning">BUFFERING</span>
          <p className="mt-2 text-sm text-tint-muted">{playback.title}</p>
        </div>
      ) : null}
      {playback.observed === "error" ? (
        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center bg-tint-bg/80">
          <span className="text-xs tracking-[0.2em] text-tint-danger">PLAYBACK ERROR</span>
          <p className="mt-2 text-sm text-tint-muted">Use the player controls or queue another source.</p>
        </div>
      ) : null}
    </div>
  )
}
