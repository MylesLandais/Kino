defmodule Harness do
  @moduledoc """
  OTP-native agent harness.

  This is **not** a TypeScript/Cordis port. It extracts DeepSeek Harness
  architectural ideas — everything is a plugin, shared context, services,
  typed events, reversible effects, ordered profiles, scoped capabilities —
  and expresses them with supervisors, Registry, PubSub, and behaviours.

  Architectural kernel: `Harness.Plugin`, `Harness.Context`, `Harness.Services`,
  `Harness.Events`, `Harness.Effect`, `Harness.Profile`, `Harness.Tools`.

  Extensions (seams only in V1): Firecracker, computer-use, recording, video,
  experience graph. Those are plugins behind service definitions, not a
  privileged core.
  """

  defdelegate start_runtime(opts), to: Harness.Runtime, as: :start_link
  defdelegate stop_runtime(runtime), to: Harness.Runtime, as: :stop
  defdelegate context(runtime), to: Harness.Runtime
end
