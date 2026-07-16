defmodule Kino.Avatar.Bootstrap do
  @moduledoc "Imports Maya's known-good demo avatar into an empty Kino catalog."

  require Logger

  alias Kino.Avatar

  @assets [
    {"vrm/Yuki.vrm", "Yuki", "Maya's default VRM model", "yuki, maya", false},
    {"animations/Idle.fbx", "Idle", "Default standing idle", "idle", true},
    {"animations/waving.fbx", "Excited Wave", "Quick waving greeting",
     "wave, waving, greet, hello", false},
    {"animations/macarena.fbx", "Macarena Dance", "Macarena dance",
     "dance, dancing, macarena, groove, boogie", false},
    {"animations/flip.fbx", "Backflip", "Do a backflip", "backflip, flip, somersault", false}
  ]

  def import_if_empty(nil), do: :disabled

  def import_if_empty(root) when is_binary(root) do
    if is_nil(Avatar.active_profile().model_asset_id) do
      import_from(root)
    else
      :already_configured
    end
  end

  def import_from(root) do
    missing =
      @assets
      |> Enum.map(&elem(&1, 0))
      |> Enum.reject(&File.regular?(Path.join(root, &1)))

    if missing == [] do
      with {:ok, assets} <- import_assets(root),
           {:ok, _profile} <- activate(assets) do
        Logger.info("Bootstrapped Kino avatar profile from #{root}")
        {:ok, assets}
      end
    else
      Logger.warning(
        "Avatar bootstrap skipped; missing from #{root}: #{Enum.join(missing, ", ")}"
      )

      {:error, {:missing_assets, missing}}
    end
  end

  defp import_assets(root) do
    Enum.reduce_while(@assets, {:ok, %{}}, fn {relative, label, description, tags, loop?},
                                              {:ok, imported} ->
      path = Path.join(root, relative)

      attrs = %{
        "label" => label,
        "description" => description,
        "tags" => tags,
        "default_loop" => loop?
      }

      case Avatar.put_asset(path, Path.basename(path), attrs, "kino:system:avatar-bootstrap") do
        {:ok, asset} -> {:cont, {:ok, Map.put(imported, Path.basename(path), asset)}}
        error -> {:halt, error}
      end
    end)
  end

  defp activate(assets) do
    Avatar.update_profile(%{
      "enabled" => true,
      "model_asset_id" => assets["Yuki.vrm"].id,
      "idle_asset_id" => assets["Idle.fbx"].id,
      "camera_distance" => 1.8,
      "look_at_camera" => true,
      "lip_sync_mode" => "viseme",
      "mouth_gain" => 6.0,
      "mouth_smoothing" => 0.5
    })
  end
end
