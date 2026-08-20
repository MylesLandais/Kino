# Harness

OTP-native agent harness for Kino. Inspired by [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) / Cordis, redesigned around BEAM primitives.

This is **not** a line-by-line TypeScript port. The architectural kernel we reproduce is:

- everything is a plugin
- plugins contribute services, events, and effects into a shared context
- there is no privileged product core
- profiles compose ordered plugin layers
- registrations are reversible
- durable session events are distinct from live extension events
- capability seams split definition / provider / consumer

Firecracker, computer-use recording, video subgraphs, and the experience graph are **extensions** we add behind those seams — not things DeepSeek already implements for us.

```text
Application → Profile → Plugin tree → Services + Events + Effects
    → Agent runtime → Environment → Experience / event store
```

## Phase 1 (this tree)

Plugin contract, explicit `Harness.Context`, service registry with scope shadowing, PubSub event bus (`emit` / `waterfall` / `serial` / `parallel`), disposers, ordered profiles, scoped tools, in-memory event log, and capability behaviours (`Harness.LLM`, `Harness.Sandbox`, `Harness.Environment`, `Harness.ComputerUse`, `Harness.Lua`, …).

```bash
cd harness
mix test
```

See `ARCHITECTURE.md` for the OTP mapping, invariants, and what not to copy from DeepSeek.
