# Tint Migration Roadmap (Kino)

Goal: replace legacy theater UI surfaces with Tint (React) while preserving Kino's OTP/PubSub backend and `/agent` websocket contract.

## Status: complete (phases 1–5)

The theater route is now a thin LiveView shell that mounts a unified Tint/React app at `#tint-theater`. All interaction flows through the `/agent` websocket channel.

### Phase 1 — Chat parity ✅

- [x] Tint chat list + composer (`TheaterChat`)
- [x] `/agent` channel receives and forwards room events
- [x] Rich agent payload mapping (`tool`, `sources`, `artifact`, `error` parts)
- [x] Slash-command hint UX in composer
- [x] Pipeline progress card with Tint-styled progress bar
- [x] Removed legacy `MessageList` hook and hidden LiveView chat DOM

### Phase 2 — Media and now-playing parity ✅

- [x] Tint `VideoPlayer` for theater playback (`TheaterPlayer`)
- [x] Playback state bound from `/agent` `playback_updated` / `theater_snapshot`
- [x] Server-authoritative desired/observed convergence preserved

### Phase 3 — Setlist/track interaction parity ✅

- [x] Setlist ported to React (`TheaterSetlist`) with seek, like, share, link expansion
- [x] `RoomSession` + `Media` APIs unchanged; UI is a pure client swap
- [x] Listen audit + qualified plays moved to `Kino.Theater.ListenAudit` via channel

### Phase 4 — Live channel modes ✅

- [x] Default mode: `chat-only`
- [x] Capability negotiation: `negotiate_capabilities` / `set_channel_mode`
- [x] Modes: `chat-only`, `live-audio`, `live-video` (control plane on `/agent`)

### Phase 5 — Cleanup ✅

- [x] Legacy LiveView theater markup removed from `TheaterLive`
- [x] Retired hooks: `VideoPlayer`, `SetList`, `MessageList`, `TheaterPreferences`, `AvatarRenderer`, `TintAgentChat`
- [x] Legacy `.kino-shell` theater CSS removed; Tint theme drives layout
- [x] Integration tests for `/agent` channel theater contract

## Architecture

```
TheaterLive (auth + mount)
    └── #tint-theater [TintTheater hook]
            └── TintTheaterApp (React)
                    ├── TheaterPlayer (tint/video-player)
                    ├── TheaterSetlist
                    ├── TheaterAvatar
                    └── TheaterChat (tint/chat)
                            ↕
                    AgentClient → /agent → AgentChannel
                            ↕
                    PubSub (room:lobby) ← RoomSession, Media, Avatar
```

## Key files

| File | Role |
|------|------|
| `assets/js/theater/TintTheaterApp.tsx` | Root React theater shell |
| `assets/js/theater/agent_client.ts` | Phoenix channel client |
| `lib/kino_web/channels/agent_channel.ex` | Websocket contract |
| `lib/kino/theater/snapshot.ex` | Theater state payloads |
| `lib/kino/theater/listen_audit.ex` | Qualified play tracking |

## Out of scope (future)

- Admin pages (`admin_*_live`) — still LiveView
- Full login/auth with Tint `SignInForm` (join form uses Tint utility classes)
- Live A/V transport (WebRTC) — modes are negotiated; media transport is a follow-on
