import type { ChatMessageData } from '../types'

const USER_COLORS: Record<string, string> = {
  natsuki: 'var(--kana-pink)',
  obata: 'var(--kana-blue)',
  reyna: 'var(--kana-green)',
  you: 'var(--kana-yellow)',
}

const STATE_META: Record<string, { icon: string; color: string; label: string }> = {
  pending:  { icon: '○', color: 'var(--kana-gray)',   label: 'pending'  },
  working:  { icon: '◌', color: 'var(--kana-yellow)', label: 'working'  },
  success:  { icon: '●', color: 'var(--kana-green)',  label: 'done'     },
  approval: { icon: '◆', color: 'var(--kana-violet)', label: 'approval' },
  error:    { icon: '✗', color: 'var(--kana-red)',    label: 'error'    },
}

interface Props {
  msg: ChatMessageData
  onApprove?: () => void
  onDeny?: () => void
  isApprovalPending?: boolean
}

export function ChatMessage({ msg, onApprove, onDeny, isApprovalPending }: Props) {
  if (msg.type === 'system') {
    return (
      <div style={{
        padding: '3px 12px',
        color: 'var(--kana-gray)',
        fontSize: 10,
        letterSpacing: '0.04em',
        borderLeft: '2px solid var(--kana-ink4)',
        marginLeft: 2,
      }}>
        <span style={{ color: 'var(--kana-ink4)', marginRight: 6 }}>{msg.ts}</span>
        {msg.text}
      </div>
    )
  }

  if (msg.type === 'agent') {
    const meta = msg.state ? STATE_META[msg.state] : null
    return (
      <div style={{
        padding: '4px 12px',
        borderLeft: `2px solid ${meta?.color ?? 'var(--kana-gray)'}`,
        marginLeft: 2,
        backgroundColor: msg.state === 'approval' ? 'rgba(149,127,184,0.06)' : 'transparent',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 2 }}>
          {meta && (
            <span style={{ color: meta.color, fontSize: 10, fontWeight: 600, letterSpacing: '0.08em' }}>
              {meta.icon} {meta.label.toUpperCase()}
            </span>
          )}
          <span style={{ color: 'var(--kana-ink4)', fontSize: 10, marginLeft: 'auto' }}>{msg.ts}</span>
        </div>
        <div style={{ color: 'var(--kana-white)', fontSize: 12 }}>{msg.text}</div>

        {/* Payload metadata */}
        {msg.payload && Object.keys(msg.payload).length > 0 && (
          <div style={{ marginTop: 4, display: 'flex', flexWrap: 'wrap', gap: '2px 10px' }}>
            {Object.entries(msg.payload).map(([k, v]) => (
              <span key={k} style={{ fontSize: 10, color: 'var(--kana-gray)' }}>
                {k}: <span style={{ color: 'var(--kana-teal)' }}>{String(v)}</span>
              </span>
            ))}
          </div>
        )}

        {/* Approval gate */}
        {msg.state === 'approval' && isApprovalPending && (
          <div style={{ marginTop: 8, display: 'flex', gap: 6 }}>
            <button
              onClick={onApprove}
              style={{
                padding: '3px 12px',
                backgroundColor: 'transparent',
                border: '1px solid var(--kana-green)',
                color: 'var(--kana-green)',
                cursor: 'pointer',
                fontSize: 11,
                letterSpacing: '0.06em',
                fontFamily: 'inherit',
                borderRadius: 2,
              }}
              onMouseEnter={e => { (e.target as HTMLButtonElement).style.backgroundColor = 'rgba(152,187,108,0.12)' }}
              onMouseLeave={e => { (e.target as HTMLButtonElement).style.backgroundColor = 'transparent' }}
            >
              ▶ APPROVE
            </button>
            <button
              onClick={onDeny}
              style={{
                padding: '3px 12px',
                backgroundColor: 'transparent',
                border: '1px solid var(--kana-ink4)',
                color: 'var(--kana-gray)',
                cursor: 'pointer',
                fontSize: 11,
                letterSpacing: '0.06em',
                fontFamily: 'inherit',
                borderRadius: 2,
              }}
              onMouseEnter={e => { (e.target as HTMLButtonElement).style.borderColor = 'var(--kana-red)'; (e.target as HTMLButtonElement).style.color = 'var(--kana-red)' }}
              onMouseLeave={e => { (e.target as HTMLButtonElement).style.borderColor = 'var(--kana-ink4)'; (e.target as HTMLButtonElement).style.color = 'var(--kana-gray)' }}
            >
              ✗ DENY
            </button>
          </div>
        )}
      </div>
    )
  }

  // user message
  const color = USER_COLORS[msg.user ?? ''] ?? 'var(--kana-fg)'
  const isOwn = msg.user === 'you'
  const isCommand = msg.text.startsWith('/')

  return (
    <div style={{ padding: '2px 12px 2px 14px' }}>
      <span style={{ color, fontSize: 11, fontWeight: 600 }}>{msg.user}</span>
      <span style={{ color: 'var(--kana-ink4)', fontSize: 10, marginLeft: 6 }}>{msg.ts}</span>
      <div style={{
        color: isCommand ? 'var(--kana-violet)' : 'var(--kana-fg)',
        fontSize: 12,
        lineHeight: 1.5,
        opacity: isOwn ? 0.9 : 1,
      }}>
        {msg.text}
      </div>
    </div>
  )
}
