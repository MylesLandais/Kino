defmodule Harness.ProfileTest do
  use ExUnit.Case, async: true

  alias Harness.Profile

  test "compose stacks layers in order and later ids replace earlier ones" do
    base = Profile.new(:base, [%{id: :core, plugin: Harness.Plugins.EventLog}])
    extra = Profile.new(:cu, [%{id: :sandbox, plugin: Harness.Plugins.LocalSandbox}])

    overlay =
      Profile.new(:user, [%{id: :core, plugin: Harness.Plugins.EventLog, config: %{x: 1}}])

    composed = Profile.compose([base, extra, overlay])
    ids = Enum.map(composed.layers, & &1.id)
    assert ids == [:core, :sandbox]
    assert hd(composed.layers).config == %{x: 1}
  end
end
