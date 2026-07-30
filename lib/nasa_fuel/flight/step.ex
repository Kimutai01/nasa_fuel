defmodule NasaFuel.Flight.Step do
  @moduledoc """
  A single manoeuvre in a flight path: an action performed at a planet.

  Embedded in `NasaFuel.Flight.Mission`; never persisted. `Ecto.Enum` rejects
  actions and planets outside the supported sets, which covers the selection
  validation the form needs.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NasaFuel.Flight.Planet

  @actions [:launch, :land]

  @type action :: :launch | :land
  @type t :: %__MODULE__{action: action() | nil, planet: Planet.t() | nil}

  @primary_key false
  embedded_schema do
    field :action, Ecto.Enum, values: @actions
    field :planet, Ecto.Enum, values: Planet.names()
  end

  @doc "Actions as `{label, value}` pairs for a select input."
  @spec action_options() :: [{String.t(), action()}]
  def action_options, do: Enum.map(@actions, &{label(&1), &1})

  @spec label(action()) :: String.t()
  def label(action) when action in @actions do
    action |> Atom.to_string() |> String.capitalize()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(step, attrs) do
    step
    |> cast(attrs, [:action, :planet])
    |> validate_required([:action, :planet])
  end
end
