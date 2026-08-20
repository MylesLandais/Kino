defmodule Adaptation.Providers.LoRA do
  @moduledoc """
  Thin CLI boundary around the Vast.ai dark-factory LoRA pipeline.

  Does not live in the agent supervision tree. Scripts are invoked out of
  process; this module only parses the CLI JSON contract.
  """

  @behaviour Adaptation.Provider

  alias Adaptation.Providers.CLI

  @impl true
  def build_dataset(trajectories, config) do
    dir = config[:dataset_dir] || Path.join(System.tmp_dir!(), "adaptation-datasets")
    File.mkdir_p!(dir)
    path = Path.join(dir, "dataset-#{System.unique_integer([:positive])}.jsonl")

    rows =
      Enum.map(trajectories, fn t ->
        Jason.encode!(%{
          id: t.id,
          domain: t.domain,
          bin: t.bin,
          evaluator_score: t.evaluator_score,
          run_uris:
            Enum.map(t.experience_runs || [], fn run ->
              %{
                id: run.id,
                video_uri: run.video_uri,
                hid_log_uri: run.hid_log_uri,
                tool_call_log_uri: run.tool_call_log_uri,
                outcome: run.outcome,
                reward: run.reward
              }
            end)
        })
      end)

    File.write!(path, Enum.join(rows, "\n") <> "\n")
    {:ok, path}
  end

  @impl true
  def train(dataset_path, base_model, config) do
    bin = bin(config, :train_bin, "VASTAI_LORA_TRAIN", "vastai-lora-train")
    args = CLI.train_args(dataset_path, base_model, config)
    run(bin, args, &CLI.parse_train/2)
  end

  @impl true
  def evaluate(artifact, suites, config) do
    bin = bin(config, :eval_bin, "VASTAI_LORA_EVAL", "vastai-lora-eval")
    args = CLI.eval_args(artifact.artifact_uri, suites, config)
    run(bin, args, &CLI.parse_eval/2)
  end

  defp bin(config, key, env, default) do
    config[key] ||
      Application.get_env(:kino, Adaptation, [])[key] ||
      System.get_env(env) ||
      default
  end

  defp run(bin, args, parser) do
    case System.cmd(bin, args, stderr_to_stdout: true) do
      {stdout, status} -> parser.(stdout, status)
    end
  rescue
    error -> {:error, {:cli_failed, bin, error}}
  end
end
