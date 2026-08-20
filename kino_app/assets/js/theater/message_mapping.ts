import type {ChatMessageData} from "tint/chat"
import type {AgentEvent, TheaterMsg} from "./types"

function actorFromTheaterMsg(msg: TheaterMsg) {
  const kind =
    msg.type === "system" ? "system" : msg.type === "agent" ? "assistant" : "human"
  const id = msg.user || kind
  return {id, name: msg.user || kind, kind}
}

function agentStateToStatus(state: unknown) {
  switch (String(state)) {
    case "pending":
    case "working":
    case "resolving":
      return "streaming"
    case "success":
      return "complete"
    case "error":
      return "error"
    default:
      return "complete"
  }
}

function agentStateToToolStatus(state: unknown) {
  switch (String(state)) {
    case "pending":
      return "pending"
    case "working":
    case "resolving":
      return "running"
    case "success":
      return "succeeded"
    case "error":
      return "failed"
    default:
      return "succeeded"
  }
}

function parseWishLinks(text: string) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .flatMap((line) => {
      const match = line.match(/^(.+?)\s+(\d+)%\s+—\s+(https?:\/\/\S+)/)
      if (!match) return []
      return [{id: match[3], title: match[1].trim(), url: match[3], citation: `${match[2]}%`}]
    })
}

function richPartsFromPayload(state: unknown, text: string, payload: Record<string, unknown>) {
  const parts: any[] = []
  const seq = Date.now()

  if (payload.artist && payload.title) {
    parts.push({
      id: `agent-tool-${seq}`,
      type: "tool",
      tool: {
        id: `tool-${seq}`,
        name: "platform-search",
        title: "Platform search",
        status: agentStateToToolStatus(state),
        input: payload,
        summary: `${payload.artist} — ${payload.title}`,
      },
    })
  }

  if (payload.cache_key) {
    parts.push({
      id: `agent-artifact-${seq}`,
      type: "artifact",
      kind: "media-cache",
      title: String(payload.title || payload.cache_key),
      data: payload,
      description: "Cached media asset",
    })
  }

  if (payload.matched && typeof payload.matched === "number") {
    const sources = parseWishLinks(text)
    if (sources.length > 0) {
      parts.push({id: `agent-sources-${seq}`, type: "sources", sources})
    }
  }

  if (String(state) === "error") {
    parts.push({id: `agent-error-${seq}`, type: "error", message: text, recoverable: false})
  } else if (text) {
    parts.push({
      id: `agent-text-${seq}`,
      type: "text",
      text,
      format: "plain",
    })
  }

  return parts.length > 0 ? parts : [{id: `agent-text-${seq}`, type: "text", text, format: "plain"}]
}

export function toTintMessageFromUserMsg(msg: TheaterMsg): ChatMessageData {
  return {
    id: String(msg.id),
    actor: actorFromTheaterMsg(msg) as any,
    createdAt: new Date().toISOString(),
    parts: [{id: `${msg.id}-p0`, type: "text", text: msg.text, format: "plain"} as any],
    status: "complete",
    metadata: msg.payload || {},
  }
}

export function toTintMessageFromAgentEvent(params: AgentEvent & {seq: number}): ChatMessageData {
  const {seq, state, text, payload} = params
  return {
    id: `agent-${seq}`,
    actor: {id: "kino-agent", name: "kino-agent", kind: "assistant"},
    createdAt: new Date().toISOString(),
    status: agentStateToStatus(state) as any,
    parts: richPartsFromPayload(state, text, payload || {}),
    metadata: payload || {},
  }
}
