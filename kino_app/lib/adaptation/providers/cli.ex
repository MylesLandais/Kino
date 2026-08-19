defmodule Adaptation.Providers.CLI do
  @moduledoc """
  v1 JSON contract for Vast.ai LoRA CLI wrappers.

  Sign-off target for `vastai-lora-train` / `vastai-lora-eval`. Until those
  binaries exist, `Adaptation.Providers.LoRA` still speaks this schema so a
  script drop-in does not change the supervision tree.

  Train (`--output-format json` on stdout):

      {
        "schema_version": 1,
        "ok": true,
        "artifact_uri": "s3://bucket/adapters/osrs/v3.safetensors",
        "version": "v3",
        "metrics": {"train_loss": 0.12},
        "provider": "lora"
      }

  Eval:

      {
        "schema_version": 1,
        "ok": true,
        "suites": {
          "combat": {"score": 0.81, "passed": true}
        }
      }

  Failure is `{"schema_version": 1, "ok": false, "error": "reason"}` or a
  non-zero exit. Args:

      vastai-lora-train --dataset PATH --base-model NAME [--config PATH] --output-format json
      vastai-lora-eval --artifact URI --suites suite1,suite2 --output-format json
  """

  @schema_version 1

  def schema_version, do: @schema_version

  def train_args(dataset_path, base_model, config) do
    ["--dataset", dataset_path, "--base-model", base_model, "--output-format", "json"]
    |> maybe_config(config)
  end

  def eval_args(artifact_uri, suites) do
    [
      "--artifact",
      artifact_uri,
      "--suites",
      Enum.join(suites, ","),
      "--output-format",
      "json"
    ]
  end

  def parse_train(stdout, exit_status) do
    with :ok <- ok_status(exit_status),
         {:ok, payload} <- decode(stdout),
         :ok <- require_ok(payload),
         {:ok, uri} <- fetch_string(payload, "artifact_uri"),
         {:ok, version} <- fetch_string(payload, "version") do
      {:ok,
       %{
         artifact_uri: uri,
         version: version,
         metrics: Map.get(payload, "metrics", %{}),
         provider: Map.get(payload, "provider", "lora")
       }}
    end
  end

  def parse_eval(stdout, exit_status) do
    with :ok <- ok_status(exit_status),
         {:ok, payload} <- decode(stdout),
         :ok <- require_ok(payload) do
      {:ok, Map.get(payload, "suites", %{})}
    end
  end

  defp maybe_config(args, config) do
    case config[:config_path] || config["config_path"] do
      path when is_binary(path) and path != "" -> args ++ ["--config", path]
      _ -> args
    end
  end

  defp ok_status(0), do: :ok
  defp ok_status(status), do: {:error, {:cli_exit, status}}

  defp decode(stdout) do
    stdout
    |> String.trim()
    |> String.split("\n")
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, map} -> {:ok, map}
        _ -> nil
      end
    end) || {:error, {:invalid_json, stdout}}
  end

  defp require_ok(%{"ok" => false, "error" => reason}), do: {:error, reason}
  defp require_ok(%{"ok" => false}), do: {:error, :cli_failed}
  defp require_ok(%{"ok" => true}), do: :ok
  defp require_ok(_), do: {:error, :missing_ok}

  defp fetch_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing, key}}
    end
  end
end
