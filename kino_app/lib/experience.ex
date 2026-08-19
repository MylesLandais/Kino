defmodule Experience.Run do
  @moduledoc """
  Immutable captured run. Experience Substrate owns this row.

  Live agents must not read these rows back into a context window.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "experience_runs" do
    field(:domain, :string)
    field(:environment_id, :string)
    field(:video_uri, :string)
    field(:hid_log_uri, :string)
    field(:tool_call_log_uri, :string)
    field(:outcome, :string)
    field(:reward, :float)
    field(:attrs, :map, default: %{})

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :domain,
      :environment_id,
      :video_uri,
      :hid_log_uri,
      :tool_call_log_uri,
      :outcome,
      :reward,
      :attrs
    ])
    |> validate_required([:domain])
  end
end

defmodule Experience do
  @moduledoc """
  Experience Substrate: append-only logging of aligned multimodal trajectories.

  Retrieval-as-context for live agents is forbidden. Adaptation reads these
  rows offline to compile datasets.
  """

  alias Experience.Run
  alias Kino.Repo

  @spec record_run(map()) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
  def record_run(attrs) when is_map(attrs) do
    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
  end

  def get_run!(id), do: Repo.get!(Run, id)
end
