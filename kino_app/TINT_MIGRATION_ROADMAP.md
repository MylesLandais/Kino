# Tint Migration Roadmap (Kino)

Goal: replace legacy theater UI surfaces with Tint (React) while preserving Kino's OTP/PubSub backend and `/agent` websocket contract.

## Current status

- ✅ `/agent` websocket transport added (`KinoWeb.AgentSocket`, `KinoWeb.AgentChannel`)
- ✅ First Tint vertical slice mounted (`#tint-agent-chat`)
- ✅ Shared command handling extracted into `Kino.Theater.ChatCommands`
- ✅ Existing LiveView tests remain green via temporary hidden compatibility DOM

## Principles

1. Keep backend authority in Elixir (PubSub, Oban, supervision trees).
2. Keep UI contracts transport-agnostic from Tint's perspective (session adapter/provider seams).
3. Replace surfaces incrementally; avoid freeze-and-rewrite.
4. Remove compatibility scaffolding only after equivalent Tint behavior is proven.

## Phase 1 — Chat parity (in progress)

- [x] Tint chat list + composer mounted in theater panel
- [x] `/agent` channel receives and forwards room events
- [ ] Map `agent_event.payload` into richer Tint part types (`tool`, `sources`, `artifact`)
- [ ] Add slash-command hint UX in React composer
- [ ] Move pipeline progress card into Tint component state

Exit criteria:
- Hidden `#messages` and `#message-form` can be removed without test regressions.

## Phase 2 — Media and now-playing parity

- [ ] Introduce Tint media surfaces for now-playing rail and playback state badges
- [ ] Bind playback state from PubSub/`/agent` events
- [ ] Preserve existing video + avatar hooks until equivalent React wrappers are live

Exit criteria:
- LiveView-only playback shell no longer required for core theater interaction.

## Phase 3 — Setlist/track interaction parity

- [ ] Port setlist row interactions (seek/like/share/link-expansion) into Tint React components
- [ ] Keep existing `RoomSession` and `Media` APIs; UI is a pure client swap

Exit criteria:
- Setlist behavior parity with current keyboard/mouse interactions.

## Phase 4 — Live channel modes

- [ ] Default mode: group chat + rich hypermedia
- [ ] Live mode: add control events for audio/video session lifecycle
- [ ] Introduce channel capability negotiation (`chat-only`, `live-audio`, `live-video`)

Exit criteria:
- “Twitch + Discord + ChatGPT” channel model fully represented by `/agent` event contract.

## Phase 5 — Cleanup

- [ ] Remove temporary hidden compatibility DOM in `TheaterLive`
- [ ] Remove unused legacy hooks/styles once replaced
- [ ] Add integration tests for `/agent` channel events and command dispatch

