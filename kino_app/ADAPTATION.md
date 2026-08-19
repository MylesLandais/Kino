# Adaptation Substrate

Closes the gap between "the agent has a memory system" and "the agent actually learns." The experience graph is **not** an expanding context window for a frozen model.

## Boundaries

| Layer | In this repo |
|---|---|
| Cordis substrate | `harness/` — plugins, tools, environments. No weights. |
| Agent process layer | `Adaptation.AgentProcess` under `Kino.Adaptation.AgentSupervisor` |
| Experience substrate | `Experience.record_run/1` → `experience_runs` (append-only) |
| Adaptation substrate | `Adaptation.Pipeline` + `maya_adaptation_graph` |

Live agents never read trajectories. Training never runs inside an agent process.

## Open items (decided for V1)

1. **CLI contract** — `Adaptation.Providers.CLI` schema_version `1`. Wrappers `vastai-lora-train` / `vastai-lora-eval` must print one JSON object (`--output-format json`) as documented in that module. The LoRA provider is a `System.cmd` boundary; swapping Kohya for QLoRA does not touch OTP trees.
2. **Promotion thresholds** — table `adaptation_domain_thresholds` (`domain`, `benchmark_suite`, `metric`, `threshold`, `comparison`). Seeded for `computer_use`, `coding`, and `osrs`. Pipeline loads suites from this table; nothing is hardcoded in the worker.
3. **Supervision** — `Kino.Adaptation.Supervisor` (child of `Kino.Supervisor`) owns `Kino.Adaptation.Registry` and `Kino.Adaptation.AgentSupervisor`. Agents are `restart: :transient`. Training uses Oban queue `adaptation` (concurrency 1), not the agent DynamicSupervisor.

## Pipeline

```
Experience.record_run
  → Adaptation.ingest_run (evaluator filter → trajectory bin)
  → Adaptation.enqueue_train(domain)   # Oban, async
  → Provider.build_dataset / train / evaluate
  → threshold check
  → promote | reject
  → PubSub "adaptation:<domain>"
  → AgentProcess adopts URI (reference swap)
```

## Graph

`CREATE PROPERTY GRAPH maya_adaptation_graph` over the vertex/edge tables. Lineage walks use `GRAPH_TABLE`, not JSON blobs.
