import { useState } from 'react'
import { VideoPlayer } from './components/VideoPlayer'
import { ChatSidebar } from './components/ChatSidebar'
import type { PlaybackItem, ChatMessageData } from './types'

const INITIAL_MESSAGES: ChatMessageData[] = [
  {
    id: '1', type: 'system', ts: '19:02:11',
    text: 'kino session started — /play <url> to queue a video',
  },
  {
    id: '2', type: 'user', ts: '19:02:34', user: 'natsuki',
    text: 'anyone got the new Tarkovsky restoration link?',
  },
  {
    id: '3', type: 'user', ts: '19:02:41', user: 'obata',
    text: '/play https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  },
  {
    id: '4', type: 'agent', ts: '19:02:41',
    text: 'Resolving video metadata…',
    state: 'pending',
    payload: { url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' },
  },
  {
    id: '5', type: 'agent', ts: '19:02:43',
    text: 'Cache miss — enqueueing yt-dlp worker',
    state: 'working',
    payload: { jobId: 'oban:2847', cacheKey: 'dQw4w9WgXcQ:1080p' },
  },
  {
    id: '6', type: 'user', ts: '19:03:01', user: 'reyna',
    text: 'oh nice, seaweed bucket cache?',
  },
  {
    id: '7', type: 'agent', ts: '19:03:22',
    text: 'Download complete — stored to s3://kino-media/dQw4w9WgXcQ:1080p.mp4 (142 MB)',
    state: 'success',
    payload: { jobId: 'oban:2847', bytes: 148897792, duration: '3:32' },
  },
  {
    id: '8', type: 'agent', ts: '19:03:22',
    text: 'Ready to play — awaiting host approval',
    state: 'approval',
    payload: { title: 'Rick Astley — Never Gonna Give You Up', duration: '3:32', requestedBy: 'obata' },
  },
]

const INITIAL_PLAYBACK: PlaybackItem = {
  id: 'idle',
  state: 'idle',
  desiredState: 'idle',
  observedState: 'idle',
  title: null,
  requestedBy: null,
  duration: null,
  cacheKey: null,
  providerCapability: null,
}

export default function App() {
  const [messages, setMessages] = useState<ChatMessageData[]>(INITIAL_MESSAGES)
  const [playback, setPlayback] = useState<PlaybackItem>(INITIAL_PLAYBACK)
  const [approvalPending, setApprovalPending] = useState<ChatMessageData | null>(
    INITIAL_MESSAGES.find(m => m.state === 'approval') ?? null
  )

  const handleApprove = () => {
    const item = approvalPending
    if (!item) return
    setApprovalPending(null)
    setPlayback({
      id: 'dQw4w9WgXcQ',
      state: 'playing',
      desiredState: 'playing',
      observedState: 'buffering',
      title: String(item.payload?.title ?? 'Unknown'),
      requestedBy: item.payload?.requestedBy ? String(item.payload.requestedBy) : null,
      duration: item.payload?.duration ? String(item.payload.duration) : null,
      cacheKey: 'dQw4w9WgXcQ:1080p',
      providerCapability: 'cached-s3',
    })
    setMessages(prev => [
      ...prev.filter(m => m.id !== item.id),
      {
        id: `${Date.now()}`, type: 'system', ts: timestamp(),
        text: `▶ Now playing: ${item.payload?.title} — approved by host`,
      },
    ])
    // Simulate observed state settling
    setTimeout(() => {
      setPlayback(p => ({ ...p, observedState: 'playing' }))
    }, 1800)
  }

  const handleDeny = () => {
    if (!approvalPending) return
    setMessages(prev => [
      ...prev.filter(m => m.id !== approvalPending.id),
      {
        id: `${Date.now()}`, type: 'system', ts: timestamp(),
        text: `✗ Queue request denied by host`,
      },
    ])
    setApprovalPending(null)
  }

  const handleSendMessage = (text: string) => {
    const isPlay = text.startsWith('/play ')
    const newMsgs: ChatMessageData[] = [
      {
        id: `${Date.now()}`, type: 'user', ts: timestamp(), user: 'you',
        text,
      },
    ]
    if (isPlay) {
      const url = text.slice(6).trim()
      newMsgs.push({
        id: `${Date.now() + 1}`, type: 'agent', ts: timestamp(),
        text: 'Resolving video metadata…',
        state: 'pending',
        payload: { url },
      })
      setMessages(prev => [...prev, ...newMsgs])
      // Simulate pipeline
      setTimeout(() => {
        setMessages(prev => [
          ...prev,
          {
            id: `${Date.now()}`, type: 'agent', ts: timestamp(),
            text: 'Cache miss — enqueueing yt-dlp worker',
            state: 'working',
            payload: { jobId: `oban:${Math.floor(Math.random() * 9000 + 1000)}`, cacheKey: 'video:1080p' },
          },
        ])
      }, 900)
      setTimeout(() => {
        const approvalMsg: ChatMessageData = {
          id: `${Date.now()}`, type: 'agent', ts: timestamp(),
          text: 'Download complete — awaiting host approval',
          state: 'approval',
          payload: { title: 'Queued video', duration: '—', requestedBy: 'you', url },
        }
        setMessages(prev => [...prev, approvalMsg])
        setApprovalPending(approvalMsg)
      }, 3200)
    } else {
      setMessages(prev => [...prev, ...newMsgs])
    }
  }

  return (
    <div style={{ display: 'flex', height: '100vh', overflow: 'hidden', backgroundColor: 'var(--kana-ink0)' }}>
      <VideoPlayer playback={playback} />
      <ChatSidebar
        messages={messages}
        approvalPending={approvalPending}
        onSend={handleSendMessage}
        onApprove={handleApprove}
        onDeny={handleDeny}
      />
    </div>
  )
}

function timestamp() {
  return new Date().toTimeString().slice(0, 8)
}
