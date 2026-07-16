defmodule Kino.AvatarTest do
  use Kino.DataCase, async: false

  alias Kino.{Accounts, Avatar}
  alias Kino.Avatar.Bootstrap

  setup do
    Accounts.ensure_rbac!()

    {:ok, admin} =
      Accounts.bootstrap_admin(%{
        "email" => "avatar-admin@kino.test",
        "username" => "avatar-admin",
        "display_name" => "Avatar Admin",
        "password" => "correct horse battery staple"
      })

    %{admin: admin}
  end

  test "uploads use stable content-addressed ontology keys and deduplicate", %{admin: admin} do
    path = Path.join(System.tmp_dir!(), "kino-wave-#{System.unique_integer([:positive])}.fbx")
    File.write!(path, "fake fbx animation")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, asset} =
             Avatar.put_asset(
               path,
               "waving.fbx",
               %{"label" => "Wave", "tags" => "greet, hello"},
               admin
             )

    assert asset.ontology_key == "avatar:animation:sha256:#{asset.sha256}"
    assert asset.object_key == "kino/avatar/animations/#{asset.sha256}.fbx"
    assert asset.tags == ["greet", "hello"]

    assert {:ok, duplicate} = Avatar.put_asset(path, "copy.fbx", %{}, admin)
    assert duplicate.id == asset.id
    assert length(Avatar.list_assets()) == 1
  end

  test "natural chat and slash commands resolve catalog animations", %{admin: admin} do
    wave = insert_animation!(admin, "waving.fbx", "Friendly Wave", "wave,greet")
    dance = insert_animation!(admin, "macarena.fbx", "Macarena Dance", "dance,boogie")
    flip = insert_animation!(admin, "flip.fbx", "Backflip", "flip,somersault")

    assert Avatar.match_motion("hello Maya, give us a wave").id == wave.id
    assert Avatar.match_motion("/dance").id == dance.id
    assert Avatar.match_motion("do a backflip!").id == flip.id
    assert Avatar.match_motion("play the movie") == nil
  end

  test "Maya demo assets bootstrap once and activate Yuki" do
    root = maya_fixture_dir()

    assert {:ok, imported} = Bootstrap.import_if_empty(root)
    assert map_size(imported) == 5
    assert length(Avatar.list_assets()) == 5

    profile = Avatar.active_profile()
    assert profile.model_asset.label == "Yuki"
    assert profile.idle_asset.label == "Idle"
    assert profile.idle_asset.default_loop

    assert :already_configured = Bootstrap.import_if_empty(root)
    assert length(Avatar.list_assets()) == 5
  end

  test "bootstrap reports all missing files without creating catalog records" do
    root = Path.join(System.tmp_dir!(), "kino-empty-avatar-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    assert {:error, {:missing_assets, missing}} = Bootstrap.import_if_empty(root)
    assert "vrm/Yuki.vrm" in missing
    assert "animations/Idle.fbx" in missing
    assert Avatar.list_assets() == []
  end

  defp insert_animation!(admin, filename, label, tags) do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{filename}")
    File.write!(path, "animation #{filename} #{System.unique_integer()}")
    on_exit(fn -> File.rm(path) end)
    {:ok, asset} = Avatar.put_asset(path, filename, %{"label" => label, "tags" => tags}, admin)
    asset
  end

  defp maya_fixture_dir do
    root = Path.join(System.tmp_dir!(), "kino-maya-avatar-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "vrm"))
    File.mkdir_p!(Path.join(root, "animations"))
    File.write!(Path.join(root, "vrm/Yuki.vrm"), "fixture Yuki #{root}")

    for name <- ~w(Idle.fbx waving.fbx macarena.fbx flip.fbx) do
      File.write!(Path.join(root, "animations/#{name}"), "fixture #{name} #{root}")
    end

    on_exit(fn -> File.rm_rf(root) end)
    root
  end
end
