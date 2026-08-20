import {Socket, type Channel} from "phoenix"

import type {PipelineProgress, TheaterSnapshot} from "./types"

export type AgentClientHandlers = {
  onJoin?: (payload: {username: string; capabilities: string[]; channel_mode: string}) => void
  onChatMessage?: (msg: unknown) => void
  onAgentEvent?: (payload: {state: string; text: string; payload: Record<string, unknown>}) => void
  onPipelineProgress?: (progress: PipelineProgress) => void
  onTheaterSnapshot?: (snapshot: TheaterSnapshot) => void
  onTheaterPatch?: (patch: Partial<TheaterSnapshot>) => void
  onPlaybackUpdated?: (playback: TheaterSnapshot["playback"]) => void
  onAvatarProfile?: (profile: unknown) => void
  onAvatarAnimation?: (payload: unknown) => void
  onChannelModeChanged?: (payload: {mode: string; capabilities: string[]}) => void
}

export class AgentClient {
  socket: Socket
  channel: Channel | null = null
  handlers: AgentClientHandlers
  authToken?: string

  constructor(handlers: AgentClientHandlers & {authToken?: string} = {}) {
    const {authToken, ...rest} = handlers as AgentClientHandlers & {authToken?: string}
    this.handlers = rest
    this.authToken = authToken
    const params: Record<string, string> = {}
    if (authToken) params.auth_token = authToken
    this.socket = new Socket("/agent", {params})
  }

  connect() {
    this.socket.connect()
    this.channel = this.socket.channel("agent:lobby", {})

    this.channel
      .join()
      .receive("ok", (resp) => this.handlers.onJoin?.(resp))
      .receive("error", () => {})

    this.channel.on("chat_message", ({msg}) => this.handlers.onChatMessage?.(msg))
    this.channel.on("agent_event", (payload) => this.handlers.onAgentEvent?.(payload))
    this.channel.on("pipeline_progress", ({progress}) => this.handlers.onPipelineProgress?.(progress))
    this.channel.on("theater_snapshot", ({snapshot}) => this.handlers.onTheaterSnapshot?.(snapshot))
    this.channel.on("theater_patch", (patch) => this.handlers.onTheaterPatch?.(patch))
    this.channel.on("playback_updated", ({playback}) => this.handlers.onPlaybackUpdated?.(playback))
    this.channel.on("avatar_profile", (profile) => this.handlers.onAvatarProfile?.(profile))
    this.channel.on("avatar_animation", (payload) => this.handlers.onAvatarAnimation?.(payload))
    this.channel.on("channel_mode_changed", (payload) => this.handlers.onChannelModeChanged?.(payload))
  }

  disconnect() {
    this.channel?.leave()
    this.socket.disconnect()
    this.channel = null
  }

  push(event: string, payload: Record<string, unknown> = {}) {
    return this.channel?.push(event, payload)
  }

  commandHint(text: string) {
    return new Promise<string | null>((resolve) => {
      this.push("command_hint", {text})
        ?.receive("ok", ({hint}: {hint: string | null}) => resolve(hint))
        ?.receive("error", () => resolve(null))
    })
  }

  chatSend(text: string) {
    return new Promise<void>((resolve) => {
      this.push("chat_send", {text})?.receive("ok", () => resolve())?.receive("error", () => resolve())
    })
  }

  playbackIntent(desired: "playing" | "paused") {
    this.push("playback_intent", {desired})
  }

  observedPlayback(payload: Record<string, unknown>) {
    this.push("observed_playback", payload)
  }

  toggleLike(position: number) {
    this.push("toggle_like", {position: String(position)})
  }

  setChannelMode(mode: string) {
    this.push("set_channel_mode", {mode})
  }

  negotiateCapabilities(requested: string[]) {
    return new Promise<{granted: string[]; mode: string; capabilities: string[]} | null>(
      (resolve) => {
        this.push("negotiate_capabilities", {requested})
          ?.receive("ok", (resp) => resolve(resp))
          ?.receive("error", () => resolve(null))
      },
    )
  }

  requestAvatarProfile() {
    return new Promise<unknown>((resolve) => {
      this.push("avatar_profile_request", {})
        ?.receive("ok", (profile) => resolve(profile))
        ?.receive("error", () => resolve(null))
    })
  }
}

export function getListenerId() {
  const key = "kino:listener-id"
  let id = window.localStorage.getItem(key)
  if (!id) {
    id = window.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`
    window.localStorage.setItem(key, id)
  }
  return id
}
