defmodule NasaFuel.Flight.Planet do
  @moduledoc """
  The celestial bodies a mission can launch from or land on.

  Gravity is in m/s². Supporting another body means adding one entry here — the
  form options, the `Ecto.Enum` validation on `NasaFuel.Flight.Step` and the
  calculator all derive from this list.
  """

  @planets [
    {:earth, 9.807},
    {:moon, 1.62},
    {:mars, 3.711}
  ]

  @names Enum.map(@planets, &elem(&1, 0))
  @gravities Map.new(@planets)

  @type t :: :earth | :moon | :mars

  @doc "Every supported planet, in display order."
  @spec names() :: [t()]
  def names, do: @names

  @doc "Planets as `{label, value}` pairs for a select input."
  @spec options() :: [{String.t(), t()}]
  def options, do: Enum.map(@names, &{label(&1), &1})

  @doc """
  Surface gravity for a planet.

  Returns `:error` for anything unsupported rather than raising, so a bad value
  surfaces as a validation failure instead of crashing the LiveView.
  """
  @spec gravity(t() | any()) :: {:ok, float()} | :error
  def gravity(planet), do: Map.fetch(@gravities, planet)

  @spec label(t()) :: String.t()
  def label(planet) when planet in @names do
    planet |> Atom.to_string() |> String.capitalize()
  end
end
