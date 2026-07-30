defmodule NasaFuel.Flight.Mission do
  @moduledoc """
  A spacecraft mass paired with the flight path it has to fly.

  This is an `embedded_schema`: it exists to validate user input and back the
  form, and is never written to a database.

  Beyond the per-field checks, the path is validated as a whole: consecutive
  steps have to describe a manoeuvre the ship could actually fly. See
  `validate_continuity/1`.
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
    |> validate_continuity()
  end

  # A flight path has to be flyable: a ship already in flight cannot launch
  # again, one already on the ground cannot land again, and it can only depart
  # from wherever it last touched down.
  #
  # Deliberately *not* enforced: that a path opens with a launch. The brief
  # costs landing Apollo 11 on Earth as a mission in its own right, so a path
  # beginning with a landing is legitimate input rather than a mistake.
  defp validate_continuity(changeset) do
    steps = get_field(changeset, :steps) || []

    case continuity_error(steps) do
      nil -> changeset
      message -> add_error(changeset, :steps, message)
    end
  end

  # Only judged once every step is complete. A half-filled step is already
  # reporting "can't be blank", and a second complaint about a path it cannot
  # form yet is noise.
  defp continuity_error(steps) do
    if Enum.all?(steps, &complete?/1) do
      steps
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.find_value(&transition_error/1)
    end
  end

  defp complete?(%Step{action: action, planet: planet}) do
    not is_nil(action) and not is_nil(planet)
  end

  defp transition_error([%Step{action: :launch}, %Step{action: :launch}]) do
    "cannot launch twice without landing in between"
  end

  defp transition_error([%Step{action: :land}, %Step{action: :land}]) do
    "cannot land twice without launching in between"
  end

  defp transition_error([%Step{action: :land, planet: from}, %Step{action: :launch, planet: to}])
       when from != to do
    "must launch from the planet it last landed on"
  end

  defp transition_error(_pair), do: nil
end
