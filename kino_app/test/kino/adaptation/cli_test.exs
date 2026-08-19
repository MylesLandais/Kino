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
end
