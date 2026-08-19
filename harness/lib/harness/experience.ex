defmodule Harness.Experience do
  @moduledoc """
  Temporal experience: observation → decision → action → transition → outcome.

  This is the experience graph node, distinct from the runtime subgraph
  (what is executing now).
  """

  defstruct [
    :run_id,
    :observation,
    :decision,
    :action,
    :transition,
    :outcome,
    artifacts: []
  ]

  @type t :: %__MODULE__{}
end

defmodule Harness.Subgraph.Node do
  @moduledoc "A supervised execution node. The graph is a runtime object, not a picture."

  defstruct [
    :id,
    :type,
    :status,
    :parent_id,
    metadata: %{}
  ]

  @type type :: :tool | :agent | :evaluation | :observation | :environment
  @type status :: :pending | :running | :completed | :failed
  @type t :: %__MODULE__{
          id: term(),
          type: type(),
          status: status(),
          parent_id: term(),
          metadata: map()
        }
end

defmodule Harness.Subgraph.Edge do
  defstruct [:from, :to, :kind]
  @type t :: %__MODULE__{from: term(), to: term(), kind: atom()}
end

defmodule Harness.Skill do
  @moduledoc "Durable derived artifact. Never persist a skill without provenance."

  defstruct [
    :id,
    :policy,
    :version,
    source_episodes: [],
    experiences: [],
    evaluations: [],
    artifacts: []
  ]

  @type t :: %__MODULE__{}
end
