defmodule NasaFuel.ChangesetHelpers do
  @moduledoc """
  Helpers for asserting on changeset errors.
  """

  @doc """
  Reduces a changeset's errors to a map of interpolated messages.

      errors_on(changeset)
      #=> %{mass: ["must be greater than 0"]}

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%\{(\w+)\}", message, fn _whole, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
