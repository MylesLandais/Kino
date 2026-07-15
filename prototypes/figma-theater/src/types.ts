export interface PlaybackItem {
  id: string
  state: 'idle' | 'buffering' | 'playing' | 'paused' | 'error'
  desiredState: 'idle' | 'playing' | 'paused'
  observedState: 'idle' | 'buffering' | 'playing' | 'paused' | 'error'
  title: string | null
  requestedBy: string | null
  duration: string | null
  cacheKey: string | null
  providerCapability: 'cached-s3' | 'stream-direct' | 'transcode-pending' | null
}

export interface ChatMessageData {
  id: string
  type: 'user' | 'system' | 'agent'
  ts: string
  user?: string
  text: string
  state?: 'pending' | 'working' | 'success' | 'approval' | 'error'
  payload?: Record<string, unknown>
}
