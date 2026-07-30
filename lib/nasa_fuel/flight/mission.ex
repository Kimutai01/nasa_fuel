defmodule NasaFuel.Flight.Mission do
  @moduledoc """
  A spacecraft mass paired with the flight path it has to fly.

  This is an `embedded_schema`: it exists to validate user input and back the
  form, and is never written to a database.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias NasaFuel.Flight.Step

  @type t :: %__MODULE__{mass: pos_integer() | nil, steps: [Step.t()]}

  @primary_key false
  embedded_schema do
    field :mass, :integer
    embeds_many :steps, Step, on_replace: :delete
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(mission, attrs \\ %{}) do
    mission
    |> cast(attrs, [:mass])
    |> validate_required([:mass])
    |> validate_number(:mass, greater_than: 0)
    |> cast_embed(:steps, required: true)
  end
end
