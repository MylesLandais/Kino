import React, {useEffect, useMemo, useState} from "react"
import {
  ChatComposer,
  ChatConversation,
  ChatMessageList,
  type ChatComposerState,
  type ChatMessageData,
} from "tint/chat"

import type {AgentClient} from "./agent_client"
import type {PipelineProgress, TheaterMsg} from "./types"
import {toTintMessageFromAgentEvent, toTintMessageFromUserMsg} from "./message_mapping"

type Props = {
  client: AgentClient
  currentActorId?: string
  messages: readonly ChatMessageData[]
  pipeline: PipelineProgress | null
  composerState: ChatComposerState
  onComposerStateChange: (state: ChatComposerState) => void
}

export function TheaterChat({
  client,
  currentActorId,
  messages,
  pipeline,
  composerState,
  onComposerStateChange,
}: Props) {
  const [draft, setDraft] = useState("")
  const [hint, setHint] = useState<string | null>(null)

  return (
    <ChatConversation label="Kino agent chat" className="flex min-h-0 flex-1 flex-col border-l border-tint-border">
      <header className="flex items-center justify-between border-b border-tint-border px-3 py-2 text-xs uppercase tracking-wide text-tint-muted">
        <span>Chat</span>
        <small className="inline-flex items-center gap-1">
          <i className="inline-block size-2 rounded-full bg-tint-success" /> online
        </small>
      </header>
      {currentActorId ? (
        <nav className="border-b border-tint-border px-3 py-1 text-sm">
          <strong>{currentActorId}</strong>
        </nav>
      ) : null}
      <ChatMessageList
        messages={messages}
        currentActorId={currentActorId}
        followOutput
        loading={false}
        emptyState="No messages yet."
      />
      {pipeline ? (
        <div className="border-t border-tint-border px-3 py-2">
          <div className="text-xs text-tint-muted">
            caching full quality{pipeline.percent ? ` · ${pipeline.percent}%` : ""}
          </div>
          <div className="mt-1 h-1.5 overflow-hidden rounded bg-tint-surface">
            <div
              className="h-full bg-tint-accent transition-all"
              style={{width: `${Math.min(pipeline.percent || 8, 100)}%`}}
            />
          </div>
        </div>
      ) : null}
      {hint ? <div className="px-3 pb-1 text-xs text-tint-warning">{hint}</div> : null}
      <ChatComposer
        value={draft}
        onValueChange={(value) => {
          setDraft(value)
          void client.commandHint(value).then(setHint)
        }}
        placeholder="message or /play <url>"
        state={composerState}
        submitLabel="Send"
        onStop={() => onComposerStateChange("idle")}
        onSubmit={(payload) => {
          const text = payload.text
          if (!text.trim()) return
          void client.chatSend(text)
          setDraft("")
          setHint(null)
          onComposerStateChange("submitting")
        }}
      />
    </ChatConversation>
  )
}

export function useTheaterChatState() {
  const [currentActorId, setCurrentActorId] = useState<string>()
  const [messages, setMessages] = useState<readonly ChatMessageData[]>([])
  const [composerState, setComposerState] = useState<ChatComposerState>("idle")
  const [pipeline, setPipeline] = useState<PipelineProgress | null>(null)
  const seqRef = useMemo(() => ({current: 0}), [])

  const chatHandlers = useMemo(
    () => ({
      onJoin: (resp: {username: string}) => setCurrentActorId(String(resp.username || "")),
      onChatMessage: (msg: unknown) => {
        setMessages((prev) => [...prev, toTintMessageFromUserMsg(msg as TheaterMsg)])
      },
      onAgentEvent: (payload: {state: string; text: string; payload: Record<string, unknown>}) => {
        const seq = ++seqRef.current
        setComposerState(payload.state === "working" || payload.state === "pending" ? "streaming" : "idle")
        setMessages((prev) => [...prev, toTintMessageFromAgentEvent({...payload, seq})])
      },
      onPipelineProgress: (progress: PipelineProgress) => setPipeline(progress),
    }),
    [seqRef],
  )

  return {
    currentActorId,
    messages,
    composerState,
    setComposerState,
    pipeline,
    chatHandlers,
  }
}
