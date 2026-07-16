defmodule Kino.Accounts.Password do
  @moduledoc "Versioned PBKDF2-SHA256 password hashes using Erlang/OTP crypto."
  @iterations 310_000
  @length 32

  def hash(password) do
    salt = :crypto.strong_rand_bytes(16)
    digest = :crypto.pbkdf2_hmac(:sha256, password, salt, @iterations, @length)
    "pbkdf2_sha256$#{@iterations}$#{Base.encode64(salt)}$#{Base.encode64(digest)}"
  end

  def verify(password, encoded) when is_binary(encoded) do
    with ["pbkdf2_sha256", iterations, salt, expected] <- String.split(encoded, "$"),
         {iterations, ""} <- Integer.parse(iterations),
         {:ok, salt} <- Base.decode64(salt),
         {:ok, expected} <- Base.decode64(expected) do
      actual = :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, byte_size(expected))
      Plug.Crypto.secure_compare(actual, expected)
    else
      _ -> false
    end
  end

  def verify(_, _), do: false
end
