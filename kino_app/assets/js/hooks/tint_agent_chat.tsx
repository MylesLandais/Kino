import React, {useEffect, useMemo, useRef, useState} from "react"
import {createRoot, type Root} from "react-dom/client"
import {Socket} from "phoenix"

import {
  ChatComposer,
  ChatConversation,
  ChatMessageList,
  type ChatComposerState,
  type ChatMessageData,
} from "tint/chat"

type TheaterMsg = {
  id: number | string
  type: string
  timestamp: string
  user?: string
  text: string
  state?: string
  payload?: Record<string, unknown>
}

function actorFromTheaterMsg(msg: TheaterMsg) {
  const kind =
    msg.type === "system"
      ? "system"
      : msg.type === "agent"
        ? "assistant"
        : "human"

  const id = msg.user || kind
  return {id, name: msg.user || kind, kind}
}

function toTintMessageFromUserMsg(msg: TheaterMsg): ChatMessageData {
  return {
    id: String(msg.id),
    actor: actorFromTheaterMsg(msg) as any,
    createdAt: new Date().toISOString(),
    parts: [
      {
        id: `${msg.id}-p0`,
        type: "text",
        text: msg.text,
        format: "plain",
      } as any,
    ],
    status: "complete",
    metadata: msg.payload || {},
  }
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

function toTintMessageFromAgentEvent(params: {
  seq: number
  state: unknown
  text: string
  payload: Record<string, unknown>
}): ChatMessageData {
  const {seq, state, text, payload} = params
  return {
    id: `agent-${seq}`,
    actor: {id: "kino-agent", name: "kino-agent", kind: "assistant"},
    createdAt: new Date().toISOString(),
    status: agentStateToStatus(state) as any,
    parts: [
      {
        id: `agent-${seq}-p0`,
        type: "text",
        text,
        format: "plain",
      } as any,
    ],
    metadata: payload || {},
  }
}

function TintAgentChatApp() {
  const [currentActorId, setCurrentActorId] = useState<string | undefined>(undefined)
  const [messages, setMessages] = useState<readonly ChatMessageData[]>([])
  const [draft, setDraft] = useState("")
  const [composerState, setComposerState] = useState<ChatComposerState>("idle")
  const [hint, setHint] = useState<string | null>(null)
  const [pipelineText, setPipelineText] = useState<string | null>(null)
  const seqRef = useRef(0)
  const channelRef = useRef<any>(null)

  const phoenixSocket = useMemo(() => new Socket("/agent", {params: {}}), [])

  useEffect(() => {
    phoenixSocket.connect()

    const channel = phoenixSocket.channel("agent:lobby", {})
    channelRef.current = channel

    channel
      .join()
      .receive("ok", (resp) => {
        setCurrentActorId(String(resp.username || ""))
      })
      .receive("error", (_err) => {
        // If auth fails, Tint will render the composer but there is nowhere to send.
        // Keep the app resilient: user can reload to retry.
      })

    channel.on("chat_message", ({msg}) => {
      const theaterMsg = msg as TheaterMsg
      setMessages((prev) => [...prev, toTintMessageFromUserMsg(theaterMsg)])
    })

    channel.on("agent_event", ({state, text, payload}) => {
      const seq = ++seqRef.current
      setComposerState(state === "working" || state === "pending" ? "streaming" : "idle")
      setMessages((prev) => [
        ...prev,
        toTintMessageFromAgentEvent({seq, state, text, payload: payload || {}}),
      ])
    })

    channel.on("pipeline_progress", ({progress}) => {
      if (progress?.percent) {
        setPipelineText(`caching full quality · ${progress.percent}%`)
      } else {
        setPipelineText("caching full quality")
      }
    })

    return () => {
      channel.leave()
      phoenixSocket.disconnect()
    }
  }, [phoenixSocket])

  return (
    <ChatConversation
      label="Kino agent chat"
      className="flex min-h-0 flex-1 flex-col"
    >
      <ChatMessageList
        messages={messages}
        currentActorId={currentActorId}
        followOutput={true}
        loading={false}
        emptyState="No messages yet."
      />
      {pipelineText ? <div className="px-3 pb-1 text-xs text-tint-muted">{pipelineText}</div> : null}
      {hint ? <div className="px-3 pb-1 text-xs text-tint-warning">{hint}</div> : null}
      <ChatComposer
        value={draft}
        onValueChange={(value) => {
          setDraft(value)
          channelRef.current
            ?.push("command_hint", {text: value})
            .receive("ok", ({hint: nextHint}: {hint: string | null}) => setHint(nextHint))
        }}
        placeholder="message or /play <url>"
        state={composerState}
        submitLabel="Send"
        onStop={() => setComposerState("idle")}
        onSubmit={(payload) => {
          const text = payload.text
          if (!text.trim()) return
          channelRef.current?.push("chat_send", {text})
          setDraft("")
          setHint(null)
          setComposerState("submitting")
        }}
      />
    </ChatConversation>
  )
}

export default {
  mounted() {
    const el = this.el as HTMLElement
    el.classList.add("tint-agent-chat-root")

    const root: Root = createRoot(el)
    ;(this as any)._tintRoot = root
    root.render(
      <React.StrictMode>
        <TintAgentChatApp />
      </React.StrictMode>,
    )
  },
  destroyed() {
    const root: Root | undefined = (this as any)._tintRoot
    root?.unmount()
  },
}

