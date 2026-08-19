import {useEffect, useRef, useState} from "react"
import AvatarEngine from "../avatar/engine"

type Props = {
  profile: unknown
  animation: unknown
}

export function TheaterAvatar({profile, animation}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const engineRef = useRef<AvatarEngine | null>(null)
  const [status, setStatus] = useState("initializing")

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    try {
      engineRef.current = new AvatarEngine(canvas)
      setStatus("ready")
    } catch (error) {
      console.error("Kino avatar renderer failed", error)
      setStatus("error")
    }

    return () => {
      engineRef.current?.dispose()
      engineRef.current = null
    }
  }, [])

  useEffect(() => {
    const engine = engineRef.current
    if (!engine || !profile) return

    engine
      .configure(profile)
      .catch((error) => {
        console.error("Kino avatar profile failed", error)
        setStatus("error")
      })
  }, [profile])

  useEffect(() => {
    const engine = engineRef.current
    if (!engine || !animation) return

    engine.play(animation).catch((error) => {
      console.error("Kino avatar animation failed", error)
      setStatus("error")
    })
  }, [animation])

  return (
    <div className="pointer-events-none absolute inset-0" aria-hidden="true" data-avatar-state={status}>
      <canvas ref={canvasRef} className="h-full w-full" />
      {status === "loading" || status === "initializing" ? (
        <span className="absolute bottom-3 right-3 rounded bg-tint-panel/80 px-2 py-1 text-xs text-tint-muted">
          loading avatar…
        </span>
      ) : null}
    </div>
  )
}
