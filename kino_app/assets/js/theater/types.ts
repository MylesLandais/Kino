export type ChapterEntry = {
  position: number
  start_seconds: number
  end_seconds?: number | null
  artist?: string
  title?: string
  label?: string
}

export type PlatformLink = {
  platform: string
  url: string
  confidence: number
}

export type SetResolution = {
  resolution: {status: string}
  links: PlatformLink[]
}

export type PlaybackState = {
  media_id?: number | null
  title?: string | null
  provider?: string | null
  cache_key?: string | null
  requested_by?: string | null
  duration_seconds?: number | null
  chapters: ChapterEntry[]
  source?: string | null
  src?: string | null
  revision: number
  desired?: string
  observed?: string
  position: number
  playback_session_id?: string | null
  markers?: {time: number; label: string}[]
}

export type TheaterSnapshot = {
  username: string
  capabilities: string[]
  channel_mode: string
  playback: PlaybackState
  reactions: Record<number, string[]>
  play_counts: Record<number, number>
  set_resolutions: Record<number, SetResolution>
}

export type PipelineProgress = {
  percent?: number
  cache_key?: string
}

export type TheaterMsg = {
  id: number | string
  type: string
  timestamp: string
  user?: string
  text: string
  state?: string
  payload?: Record<string, unknown>
}

export type AgentEvent = {
  state: string
  text: string
  payload: Record<string, unknown>
}
