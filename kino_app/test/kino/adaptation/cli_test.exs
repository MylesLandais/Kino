defmodule Adaptation.CLITest do
  use ExUnit.Case, async: true

  alias Adaptation.Providers.CLI

  test "parses train JSON contract v1" do
    stdout = """
    noise
    {"schema_version":1,"ok":true,"artifact_uri":"s3://a/v1","version":"v1","metrics":{"train_loss":0.2},"provider":"lora"}
    """

    assert {:ok,
            %{
              artifact_uri: "s3://a/v1",
              version: "v1",
              provider: "lora",
              metrics: %{"train_loss" => 0.2}
            }} = CLI.parse_train(stdout, 0)
  end

  test "parses eval JSON contract v1" do
    stdout = ~s({"schema_version":1,"ok":true,"suites":{"combat":{"score":0.8,"passed":true}}})

    assert {:ok, %{"combat" => %{"score" => 0.8, "passed" => true}}} = CLI.parse_eval(stdout, 0)
  end

  test "failed ok flag is an error" do
    assert {:error, "oom"} =
             CLI.parse_train(~s({"schema_version":1,"ok":false,"error":"oom"}), 0)
  end

  test "non-zero exit is an error" do
    assert {:error, {:cli_exit, 2}} = CLI.parse_eval("{}", 2)
  end

  test "train argv is deterministic" do
    assert CLI.train_args("/data.jsonl", "llama", %{}) ==
             ["--dataset", "/data.jsonl", "--base-model", "llama", "--output-format", "json"]
  end

  test "stub flag is appended when requested" do
    assert List.last(CLI.train_args("/data.jsonl", "llama", %{stub: true})) == "--stub"
  end

  test "missing schema_version is rejected" do
    assert {:error, :missing_schema_version} =
             CLI.parse_train(~s({"ok":true,"artifact_uri":"s3://a","version":"v1"}), 0)
  end

  test "vastai-lora-train stub emits parseable contract JSON" do
    dataset = write_dataset()

    {stdout, 0} =
      System.cmd(train_bin(), [
        "--dataset",
        dataset,
        "--base-model",
        "base",
        "--output-format",
        "json",
        "--stub"
      ])

    assert {:ok, %{artifact_uri: uri, version: version, provider: "lora"}} =
             CLI.parse_train(stdout, 0)

    assert is_binary(uri) and uri != ""
    assert is_binary(version) and version != ""
  end

  test "vastai-lora-eval stub emits per-suite scores" do
    {stdout, 0} =
      System.cmd(
        eval_bin(),
        ["--artifact", "file://x.safetensors", "--suites", "combat,desktop_success", "--output-format", "json", "--stub"],
        env: Map.put(System.get_env(), "ADAPTATION_CLI_EVAL_SCORE", "0.81")
      )

    assert {:ok, suites} = CLI.parse_eval(stdout, 0)
    assert suites["combat"]["score"] == 0.81
    assert suites["desktop_success"]["passed"] == true
  end

  test "LoRA provider consumes the wrapper scripts" do
    dataset = write_dataset()

    assert {:ok, artifact} =
             Adaptation.Providers.LoRA.train(dataset, "base", %{
               train_bin: train_bin(),
               stub: true
             })

    assert {:ok, metrics} =
             Adaptation.Providers.LoRA.evaluate(artifact, ["desktop_success"], %{
               eval_bin: eval_bin(),
               stub: true
             })

    assert metrics["desktop_success"]["score"]
  end

  test "missing backend is a JSON error, not a crash" do
    dataset = write_dataset()

    {stdout, status} =
      System.cmd(train_bin(), [
        "--dataset",
        dataset,
        "--base-model",
        "base",
        "--output-format",
        "json"
      ])

    assert status != 0
    assert {:error, reason} = CLI.parse_train(stdout, status)
    assert reason == {:cli_exit, status} or is_binary(reason)
  end

  defp write_dataset do
    path = Path.join(System.tmp_dir!(), "adaptation-cli-#{System.unique_integer([:positive])}.jsonl")
    File.write!(path, "{}\n")
    path
  end

  defp train_bin do
    Application.get_env(:kino, Adaptation)[:train_bin]
  end

  defp eval_bin do
    Application.get_env(:kino, Adaptation)[:eval_bin]
  end
end
