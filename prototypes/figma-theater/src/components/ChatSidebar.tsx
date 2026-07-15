import { useRef, useEffect, useState, type KeyboardEvent } from 'react'
import { ChatMessage } from './ChatMessage'
import type { ChatMessageData } from '../types'

interface Props {
  messages: ChatMessageData[]
  approvalPending: ChatMessageData | null
  onSend: (text: string) => void
  onApprove: () => void
  onDeny: () => void
}

const ONLINE_USERS = ['natsuki', 'obata', 'reyna', 'you']

export function ChatSidebar({ messages, approvalPending, onSend, onApprove, onDeny }: Props) {
  const [input, setInput] = useState('')
  const [focused, setFocused] = useState(false)
  const bottomRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const handleKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && input.trim()) {
      onSend(input.trim())
      setInput('')
    }
  }

  const isCommand = input.startsWith('/')

  return (
    <div style={{
      width: 300,
      minWidth: 260,
      display: 'flex',
      flexDirection: 'column',
      backgroundColor: 'var(--kana-ink1)',
      borderLeft: '1px solid var(--kana-ink4)',
      overflow: 'hidden',
      flexShrink: 0,
    }}>
      {/* Header */}
      <div style={{
        padding: '8px 12px',
        borderBottom: '1px solid var(--kana-ink4)',
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        flexShrink: 0,
      }}>
        <span style={{ color: 'var(--kana-gray)', fontSize: 10, letterSpacing: '0.1em', textTransform: 'uppercase' }}>
          chat
        </span>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 4, alignItems: 'center' }}>
          <span style={{
            width: 6, height: 6, borderRadius: '50%',
            backgroundColor: 'var(--kana-green)',
            boxShadow: '0 0 6px var(--kana-green)',
            display: 'inline-block',
          }} />
          <span style={{ color: 'var(--kana-gray)', fontSize: 10 }}>{ONLINE_USERS.length}</span>
        </div>
      </div>

      {/* Online users strip */}
      <div style={{
        padding: '6px 12px',
        borderBottom: '1px solid var(--kana-ink4)',
        display: 'flex',
        gap: 8,
        flexShrink: 0,
      }}>
        {ONLINE_USERS.map(u => (
          <span key={u} style={{
            fontSize: 10,
            color: u === 'you' ? 'var(--kana-yellow)' : 'var(--kana-gray)',
            cursor: 'default',
          }}>
            {u}
          </span>
        ))}
      </div>

      {/* Approval banner */}
      {approvalPending && (
        <div style={{
          padding: '6px 12px',
          backgroundColor: 'rgba(149,127,184,0.1)',
          borderBottom: '1px solid rgba(149,127,184,0.25)',
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          flexShrink: 0,
        }}>
          <span style={{ color: 'var(--kana-violet)', fontSize: 10, fontWeight: 600, letterSpacing: '0.08em' }}>
            ◆ APPROVAL REQUIRED
          </span>
        </div>
      )}

      {/* Messages */}
      <div
        className="scroll-region"
        style={{
          flex: 1,
          overflowY: 'auto',
          display: 'flex',
          flexDirection: 'column',
          gap: 6,
          paddingTop: 8,
          paddingBottom: 8,
        }}
      >
        {messages.map(msg => (
          <ChatMessage
            key={msg.id}
            msg={msg}
            isApprovalPending={approvalPending?.id === msg.id}
            onApprove={onApprove}
            onDeny={onDeny}
          />
        ))}
        <div ref={bottomRef} />
      </div>

      {/* Slash command hint */}
      {isCommand && (
        <div style={{
          padding: '4px 12px',
          backgroundColor: 'rgba(149,127,184,0.07)',
          borderTop: '1px solid var(--kana-ink4)',
          fontSize: 10,
          color: 'var(--kana-gray)',
          flexShrink: 0,
        }}>
          {input.startsWith('/play') ? (
            <span><span style={{ color: 'var(--kana-violet)' }}>/play</span> &lt;youtube-url&gt; — fetch + cache via yt-dlp → seaweedfs</span>
          ) : (
            <span style={{ color: 'var(--kana-violet)' }}>command: {input}</span>
          )}
        </div>
      )}

      {/* Composer */}
      <div style={{
        padding: '8px 12px',
        borderTop: '1px solid var(--kana-ink4)',
        flexShrink: 0,
        backgroundColor: 'var(--kana-ink0)',
      }}>
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          border: `1px solid ${focused ? 'var(--kana-ink4)' : 'var(--kana-ink3)'}`,
          padding: '6px 10px',
          borderRadius: 2,
          transition: 'border-color 0.15s',
        }}>
          <span style={{ color: 'var(--kana-gray)', fontSize: 12, flexShrink: 0 }}>›</span>
          <input
            ref={inputRef}
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            onFocus={() => setFocused(true)}
            onBlur={() => setFocused(false)}
            placeholder="message or /play <url>"
            style={{
              flex: 1,
              background: 'transparent',
              border: 'none',
              outline: 'none',
              color: isCommand ? 'var(--kana-violet)' : 'var(--kana-fg)',
              fontSize: 12,
              fontFamily: 'inherit',
              caretColor: 'var(--kana-blue)',
            }}
          />
        </div>
        <div style={{
          marginTop: 4,
          fontSize: 9,
          color: 'var(--kana-ink4)',
          letterSpacing: '0.05em',
          display: 'flex',
          justifyContent: 'space-between',
        }}>
          <span>enter to send</span>
          <span>/play /pause /queue /clear</span>
        </div>
      </div>
    </div>
  )
}
