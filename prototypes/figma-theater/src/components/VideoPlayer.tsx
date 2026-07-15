import { useState, useEffect } from 'react'
import type { PlaybackItem } from '../types'
import { VRMOverlay } from './VRMOverlay'

interface Props {
  playback: PlaybackItem
}

const STATE_COLORS: Record<string, string> = {
  idle: 'var(--kana-gray)',
  buffering: 'var(--kana-yellow)',
  playing: 'var(--kana-green)',
  paused: 'var(--kana-orange)',
  error: 'var(--kana-red)',
}

const PROVIDER_LABELS: Record<string, string> = {
  'cached-s3': 'seaweedfs/s3',
  'stream-direct': 'stream/direct',
  'transcode-pending': 'transcode/pending',
}

export function VideoPlayer({ playback }: Props) {
  const [elapsed, setElapsed] = useState(0)
  const [avatarVisible, setAvatarVisible] = useState(false)

  useEffect(() => {
    if (playback.observedState !== 'playing') return
    const id = setInterval(() => {
      setElapsed(e => e + 1)
    }, 1000)
    return () => clearInterval(id)
  }, [playback.observedState])

  useEffect(() => {
    if (playback.state === 'idle') setElapsed(0)
  }, [playback.state])

  const isPlaying = playback.observedState === 'playing'
  const isBuffering = playback.observedState === 'buffering'
  const desiredMismatch = playback.desiredState !== playback.observedState

  return (
    <div style={{
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      backgroundColor: 'var(--kana-ink0)',
      borderRight: '1px solid var(--kana-ink4)',
      overflow: 'hidden',
    }}>
      {/* Top bar */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: 12,
        padding: '8px 14px',
        backgroundColor: 'var(--kana-ink1)',
        borderBottom: '1px solid var(--kana-ink4)',
        flexShrink: 0,
      }}>
        <span style={{ color: 'var(--kana-violet)', fontWeight: 600, letterSpacing: '0.08em', fontSize: 11 }}>
          KINO
        </span>
        <span style={{ color: 'var(--kana-ink4)', fontSize: 11 }}>│</span>
        <span style={{ color: 'var(--kana-gray)', fontSize: 11 }}>theater</span>
        {playback.title && (
          <>
            <span style={{ color: 'var(--kana-ink4)', fontSize: 11 }}>│</span>
            <span style={{ color: 'var(--kana-fg)', fontSize: 11, opacity: 0.85, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 320 }}>
              {playback.title}
            </span>
          </>
        )}
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 10 }}>
          <button
            onClick={() => setAvatarVisible(v => !v)}
            style={{
              background: 'transparent',
              border: `1px solid ${avatarVisible ? 'var(--kana-pink)' : 'var(--kana-ink4)'}`,
              color: avatarVisible ? 'var(--kana-pink)' : 'var(--kana-gray)',
              fontSize: 10,
              padding: '1px 8px',
              cursor: 'pointer',
              fontFamily: 'inherit',
              borderRadius: 2,
              letterSpacing: '0.06em',
              transition: 'all 0.15s',
            }}
          >
            ♡ avatar
          </button>
          {playback.cacheKey && (
            <span style={{ color: 'var(--kana-teal)', fontSize: 10, opacity: 0.7 }}>
              {playback.cacheKey}
            </span>
          )}
          {playback.providerCapability && (
            <span style={{
              fontSize: 10,
              padding: '1px 6px',
              border: '1px solid var(--kana-wave1)',
              color: 'var(--kana-teal)',
              borderRadius: 2,
              letterSpacing: '0.06em',
            }}>
              {PROVIDER_LABELS[playback.providerCapability]}
            </span>
          )}
        </div>
      </div>

      {/* Theater */}
      <div style={{
        flex: 1,
        position: 'relative',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: '#0D0D12',
      }}>
        {playback.state === 'idle' ? (
          <IdleState />
        ) : isBuffering ? (
          <BufferingState title={playback.title} />
        ) : (
          <PlayingState title={playback.title} elapsed={elapsed} duration={playback.duration} />
        )}

        <VRMOverlay visible={avatarVisible} />

        {/* Scanline overlay */}
        <div style={{
          position: 'absolute',
          inset: 0,
          backgroundImage: 'repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0,0,0,0.03) 2px, rgba(0,0,0,0.03) 4px)',
          pointerEvents: 'none',
        }} />
      </div>

      {/* Playback state bar */}
      <div style={{
        padding: '6px 14px',
        backgroundColor: 'var(--kana-ink1)',
        borderTop: '1px solid var(--kana-ink4)',
        display: 'flex',
        alignItems: 'center',
        gap: 16,
        flexShrink: 0,
        fontSize: 10,
        fontFamily: 'inherit',
      }}>
        {/* Desired state */}
        <StateIndicator label="desired" state={playback.desiredState} />
        <span style={{ color: 'var(--kana-ink4)' }}>→</span>
        {/* Observed state */}
        <StateIndicator label="observed" state={playback.observedState} />

        {desiredMismatch && (
          <span style={{ color: 'var(--kana-yellow)', marginLeft: 4, animation: 'none' }}>
            ⚡ state convergence pending
          </span>
        )}

        <div style={{ marginLeft: 'auto', display: 'flex', gap: 12 }}>
          {playback.requestedBy && (
            <span style={{ color: 'var(--kana-gray)' }}>
              req: <span style={{ color: 'var(--kana-pink)' }}>{playback.requestedBy}</span>
            </span>
          )}
          {playback.duration && (
            <span style={{ color: 'var(--kana-gray)' }}>
              dur: <span style={{ color: 'var(--kana-fg)' }}>{playback.duration}</span>
            </span>
          )}
          {isPlaying && (
            <span style={{ color: 'var(--kana-gray)' }}>
              t: <span style={{ color: 'var(--kana-yellow)' }}>{formatTime(elapsed)}</span>
            </span>
          )}
        </div>
      </div>
    </div>
  )
}

function StateIndicator({ label, state }: { label: string; state: string }) {
  return (
    <span style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
      <span style={{ color: 'var(--kana-gray)' }}>{label}:</span>
      <span style={{
        display: 'inline-block',
        width: 6, height: 6, borderRadius: '50%',
        backgroundColor: STATE_COLORS[state] ?? 'var(--kana-gray)',
        boxShadow: state === 'playing' ? `0 0 6px ${STATE_COLORS[state]}` : 'none',
      }} />
      <span style={{ color: STATE_COLORS[state] ?? 'var(--kana-gray)' }}>{state}</span>
    </span>
  )
}

function IdleState() {
  return (
    <div style={{ textAlign: 'center', userSelect: 'none' }}>
      <div style={{
        fontSize: 11,
        color: 'var(--kana-ink4)',
        letterSpacing: '0.15em',
        marginBottom: 12,
        textTransform: 'uppercase',
      }}>
        no source
      </div>
      <div style={{
        width: 64, height: 64, margin: '0 auto 16px',
        border: '1px solid var(--kana-ink4)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: 'var(--kana-ink4)',
        fontSize: 28,
      }}>
        ▷
      </div>
      <div style={{ color: 'var(--kana-gray)', fontSize: 11 }}>
        use <span style={{ color: 'var(--kana-violet)' }}>/play &lt;url&gt;</span> in chat to queue a video
      </div>
    </div>
  )
}

function BufferingState({ title }: { title: string | null }) {
  return (
    <div style={{ textAlign: 'center', userSelect: 'none' }}>
      <div style={{
        fontSize: 11, letterSpacing: '0.12em',
        color: 'var(--kana-yellow)',
        marginBottom: 8,
      }}>
        BUFFERING
      </div>
      {title && (
        <div style={{ color: 'var(--kana-gray)', fontSize: 12, maxWidth: 360 }}>{title}</div>
      )}
      <div style={{
        marginTop: 20,
        display: 'flex', gap: 6, justifyContent: 'center',
      }}>
        {[0, 1, 2, 3].map(i => (
          <div key={i} style={{
            width: 4, height: 16,
            backgroundColor: 'var(--kana-yellow)',
            opacity: 0.3 + i * 0.18,
            borderRadius: 1,
          }} />
        ))}
      </div>
    </div>
  )
}

function PlayingState({ title, elapsed, duration }: { title: string | null; elapsed: number; duration: string | null }) {
  const totalSecs = parseDuration(duration)
  const pct = totalSecs > 0 ? Math.min((elapsed / totalSecs) * 100, 100) : 0

  return (
    <div style={{ width: '100%', height: '100%', position: 'relative', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', padding: '0 0 0 0' }}>
      {/* Fake video content — wave pattern */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'linear-gradient(160deg, #16161D 0%, #1F1F28 40%, #2D4F67 100%)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <div style={{ opacity: 0.06, fontSize: 180, lineHeight: 1, userSelect: 'none', letterSpacing: '-0.05em' }}>
          波
        </div>
      </div>

      {/* Title overlay */}
      {title && (
        <div style={{
          position: 'absolute',
          bottom: 48, left: 20,
          backgroundColor: 'rgba(22,22,29,0.85)',
          padding: '4px 10px',
          fontSize: 12,
          color: 'var(--kana-fg)',
          backdropFilter: 'blur(4px)',
          maxWidth: '70%',
        }}>
          {title}
        </div>
      )}

      {/* Progress bar */}
      <div style={{
        position: 'absolute',
        bottom: 0, left: 0, right: 0,
        height: 3,
        backgroundColor: 'var(--kana-ink4)',
      }}>
        <div style={{
          height: '100%',
          width: `${pct}%`,
          backgroundColor: 'var(--kana-blue)',
          transition: 'width 1s linear',
          boxShadow: '0 0 8px var(--kana-blue)',
        }} />
      </div>
    </div>
  )
}

function formatTime(secs: number) {
  const m = Math.floor(secs / 60)
  const s = secs % 60
  return `${m}:${String(s).padStart(2, '0')}`
}

function parseDuration(d: string | null): number {
  if (!d) return 0
  const parts = d.split(':').map(Number)
  if (parts.length === 2) return parts[0] * 60 + parts[1]
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2]
  return 0
}
