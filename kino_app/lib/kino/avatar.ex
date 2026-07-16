defmodule Kino.Avatar do
  @moduledoc "Durable avatar catalog, active profile, motion matching, and room broadcasts."
  import Ecto.Query
  alias Kino.Avatar.{Asset, Profile}
  alias Kino.Media.Storage
  alias Kino.Repo

  @topic Kino.Media.topic()
  @aliases %{
    "wave" => ~w(wave waving greet hello goodbye),
    "dance" => ~w(dance dancing macarena groove boogie),
    "backflip" => ~w(backflip flip somersault)
  }

  def list_assets, do: Repo.all(from(a in Asset, order_by: [a.kind, a.label]))
  def get_asset!(id), do: Repo.get!(Asset, id)

  def active_profile do
    case Repo.get_by(Profile, profile_key: "theater-default") do
      nil ->
        Repo.insert!(%Profile{profile_key: "theater-default"})
        |> Repo.preload([:model_asset, :idle_asset, :idle_variants])

      profile ->
        Repo.preload(profile, [:model_asset, :idle_asset, :idle_variants])
    end
  end

  def put_asset(path, client_name, attrs, actor) do
    with {:ok, stat} <- File.stat(path),
         :ok <- validate_upload(client_name, stat.size),
         sha <- sha256(path),
         kind <- kind(client_name),
         nil <- Repo.get_by(Asset, kind: kind, sha256: sha),
         ext <- Path.extname(client_name) |> String.trim_leading(".") |> String.downcase(),
         key <-
           "kino/avatar/#{if kind == "model", do: "models", else: "animations"}/#{sha}.#{ext}",
         {:ok, %{etag: _}} <- Storage.impl().put_file(key, path) do
      values = %{
        ontology_key: "avatar:#{kind}:sha256:#{sha}",
        kind: kind,
        label: blank_default(attrs["label"], Path.rootname(Path.basename(client_name))),
        description: attrs["description"],
        tags: parse_tags(attrs["tags"]),
        default_loop: attrs["default_loop"] in [true, "true", "on"],
        format: ext,
        mime_type: if(kind == "model", do: "model/gltf-binary", else: "application/octet-stream"),
        sha256: sha,
        byte_size: stat.size,
        storage_backend: storage_name(),
        object_key: key,
        created_by_key: actor_key(actor)
      }

      case %Asset{} |> Asset.changeset(values) |> Repo.insert() do
        {:ok, asset} ->
          broadcast({:avatar_catalog_updated, asset.id})
          {:ok, asset}

        {:error, reason} ->
          Storage.impl().delete(key)
          {:error, reason}
      end
    else
      %Asset{} = asset -> {:ok, asset}
      error -> error
    end
  end

  def update_asset(id, attrs) do
    result =
      get_asset!(id)
      |> Asset.metadata_changeset(Map.update(attrs, "tags", [], &parse_tags/1))
      |> Repo.update()

    if match?({:ok, _}, result), do: broadcast({:avatar_catalog_updated, id})
    result
  end

  def delete_asset(id) do
    asset = get_asset!(id)

    referenced? =
      Repo.exists?(from(p in Profile, where: p.model_asset_id == ^id or p.idle_asset_id == ^id))

    if referenced?,
      do: {:error, :referenced},
      else: with(:ok <- Storage.impl().delete(asset.object_key), do: Repo.delete(asset))
  end

  def update_profile(attrs) do
    profile = active_profile()
    result = profile |> Profile.changeset(attrs) |> Repo.update()
    if match?({:ok, _}, result), do: broadcast({:avatar_profile_updated, "theater-default"})
    result
  end

  def signed_url(%Asset{object_key: key}) do
    case Storage.impl().public_url(key) do
      {:ok, url} -> url
      _ -> "/avatar/assets/#{get_by_key!(key).id}/content"
    end
  end

  def profile_payload do
    p = active_profile()

    %{
      enabled: p.enabled,
      camera_distance: p.camera_distance,
      look_at_camera: p.look_at_camera,
      lip_sync_mode: p.lip_sync_mode,
      mouth_gain: p.mouth_gain,
      mouth_smoothing: p.mouth_smoothing,
      model: asset_payload(p.model_asset),
      idle: asset_payload(p.idle_asset),
      idle_variants: Enum.map(p.idle_variants, &asset_payload/1)
    }
  end

  def match_motion(text) do
    normalized = text |> String.downcase() |> String.trim()
    assets = Repo.all(from(a in Asset, where: a.kind == "animation"))

    requested =
      cond do
        Regex.match?(~r{^/wave\b}, normalized) ->
          "wave"

        Regex.match?(~r{^/dance\b}, normalized) ->
          "dance"

        Regex.match?(~r{^/backflip\b}, normalized) ->
          "backflip"

        Regex.match?(~r{^/animate\s+}, normalized) ->
          String.replace_prefix(normalized, "/animate ", "")

        true ->
          Enum.find_value(@aliases, fn {motion, hints} ->
            if Enum.any?(hints, &word?(normalized, &1)), do: motion
          end)
      end

    find_asset(assets, requested, normalized)
  end

  def trigger(%Asset{} = asset) do
    broadcast(
      {:avatar_animation, %{id: asset.id, name: asset.label, url: signed_url(asset), loop: false}}
    )

    :ok
  end

  def local_path(%Asset{object_key: key}), do: Path.join(Kino.Media.cache_dir(), key)
  defp asset_payload(nil), do: nil

  defp asset_payload(asset),
    do: %{id: asset.id, label: asset.label, url: signed_url(asset), loop: asset.default_loop}

  defp get_by_key!(key), do: Repo.get_by!(Asset, object_key: key)
  defp broadcast(event), do: Phoenix.PubSub.broadcast(Kino.PubSub, @topic, event)
  defp find_asset(_, nil, _), do: nil

  defp find_asset(assets, requested, text) do
    hints = Map.get(@aliases, requested, [requested])

    Enum.max_by(
      assets,
      fn a ->
        blob =
          Enum.join([a.label, a.description, Path.rootname(a.object_key) | a.tags], " ")
          |> String.downcase()

        Enum.count(hints, &String.contains?(blob, &1)) * 10 +
          if(String.contains?(blob, requested), do: 20, else: 0) +
          if(String.contains?(text, String.downcase(a.label)), do: 30, else: 0)
      end,
      fn -> nil end
    )
    |> case do
      nil ->
        nil

      asset ->
        if Enum.any?(
             hints,
             &String.contains?(
               Enum.join([asset.label, asset.description | asset.tags], " ") |> String.downcase(),
               &1
             )
           ),
           do: asset
    end
  end

  defp word?(text, hint),
    do: Regex.match?(Regex.compile!("\\b#{Regex.escape(hint)}\\w*\\b", "i"), text)

  defp validate_upload(name, size) do
    ext = Path.extname(name) |> String.downcase()

    cond do
      ext == ".vrm" and size <= 120 * 1024 * 1024 -> :ok
      ext == ".fbx" and size <= 80 * 1024 * 1024 -> :ok
      ext not in [".vrm", ".fbx"] -> {:error, :unsupported_type}
      true -> {:error, :too_large}
    end
  end

  defp kind(name),
    do: if(Path.extname(name) |> String.downcase() == ".vrm", do: "model", else: "animation")

  defp sha256(path),
    do:
      path
      |> File.stream!([], 1_048_576)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

  defp parse_tags(tags) when is_binary(tags),
    do: tags |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp parse_tags(tags) when is_list(tags), do: tags
  defp parse_tags(_), do: []
  defp blank_default(nil, fallback), do: fallback
  defp blank_default("", fallback), do: fallback
  defp blank_default(value, _), do: String.trim(value)
  defp storage_name, do: if(Storage.impl() == Kino.Media.Storage.S3, do: "s3", else: "local")
  defp actor_key(%{id: id}), do: "kino:user:#{id}"
  defp actor_key(key) when is_binary(key), do: key
end
