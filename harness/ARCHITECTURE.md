# Harness architecture

Read [DeepSeek Harness architecture](https://deepseek-harness.github.io/deepseek-harness/en/reference/) and the [Cordis primer](https://deepseek-harness.github.io/deepseek-harness/en/reference/cordis-primer) for the *ideas*. Do not copy TypeScript `Fiber` / `ctx.tools` proxy details.

## What to reproduce conceptually

| Cordis / DeepSeek | OTP here |
| --- | --- |
| Plugin | `Harness.Plugin` + supervised `Harness.Plugin.Server` |
| Shared context | `%Harness.Context{}` passed explicitly |
| Service definition | Elixir behaviour (`Harness.LLM`, `Harness.Sandbox`, …) |
| Service provider | struct/module registered on the context |
| Consumer | depends on the behaviour only |
| Typed events | `%Harness.Event{}` with `:durable` / `:live` / `:capability` |
| `emit` / `waterfall` / `serial` / `parallel` | `Harness.Events` |
| Reversible effect | disposer `fn -> ... end`, unwind on unmount |
| Profile / bundle / patch | `Harness.Profile` ordered layers, later id wins |
| Scoped agent registrations | `Harness.Scope` chain, narrower shadows broader |
| Session log | durable events on the kernel log + `Harness.EventStore` |
| Live agent events | `agent/*` names, not appended as facts unless class is `:durable` |

## What not to copy mechanically

- No giant Agent GenServer that owns every subsystem
- No process dictionary as the context
- No global ETS that outlives the plugin
- No custom actor model, event bus, or scheduler — use supervisors, Registry, PubSub, Task.Supervisor, `:telemetry`
- No Firecracker NIF, custom Lua VM, or custom graph database in V1
- Video files are artifacts referenced by events, never the source of truth

## Kernel vs extensions

Treat plugin/context/services/events/effects/profiles, subgraph types, tools, and scoped capabilities as the kernel.

Firecracker, desktop computer-use, recording, video analysis, and the experience graph are plugins behind `Harness.Environment`, `Harness.ComputerUse`, `Harness.Storage`, and `Harness.Evaluator`.

## Invariants

1. Anything replaceable is a plugin.
2. Consumers depend on service definitions, never providers.
3. Registrations are scoped and reversible.
4. Durable facts are event-sourced; model-visible state is reconstructable from the log.
5. Runtime graph (what is executing) is not the experience graph (what happened).
