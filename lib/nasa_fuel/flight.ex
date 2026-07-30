defmodule NasaFuel.Flight do
  @moduledoc """
  Flight planning: building, validating and costing missions.

  This is the only module the web layer talks to. It owns the shape of the form
  params so the LiveView never has to reach into `Ecto.Changeset` or the
  calculator directly.
  """

  alias Ecto.Changeset
  alias NasaFuel.Flight.Fuel
  alias NasaFuel.Flight.Mission
  alias NasaFuel.Flight.Planet
  alias NasaFuel.Flight.Step

  @presets [
    %{
      id: "apollo_11",
      name: "Apollo 11",
      mass: 28_801,
      path: [launch: :earth, land: :moon, launch: :moon, land: :earth]
    },
    %{
      id: "mars_mission",
      name: "Mars mission",
      mass: 14_606,
      path: [launch: :earth, land: :mars, launch: :mars, land: :earth]
    },
    %{
      id: "passenger_ship",
      name: "Passenger ship",
      mass: 75_432,
      path: [
        launch: :earth,
        land: :moon,
        launch: :moon,
        land: :mars,
        launch: :mars,
        land: :earth
      ]
    }
  ]

  @type params :: %{optional(String.t()) => any()}

  @doc """
  Validates params and costs the mission in one step.

  Returns `{:error, changeset}` when the mission does not validate, so the
  caller can render form errors instead of a total.

  ## Examples

  A preset from the mission brief:

      iex> {:ok, result} = NasaFuel.Flight.plan(NasaFuel.Flight.preset_params("apollo_11"))
      iex> result.total
      51898

  Or a mass and path given directly. The result carries the fuel for each step
  alongside the total, in flight order:

      iex> params = %{
      ...>   "mass" => "28801",
      ...>   "steps" => [
      ...>     %{"action" => "launch", "planet" => "earth"},
      ...>     %{"action" => "land", "planet" => "moon"}
      ...>   ]
      ...> }
      iex> {:ok, result} = NasaFuel.Flight.plan(params)
      iex> result.total
      22380
      iex> Enum.map(result.steps, & &1.fuel)
      [20845, 1535]

  """
  @spec plan(params()) :: {:ok, Fuel.result()} | {:error, Changeset.t() | Fuel.error()}
  def plan(params) do
    params
    |> normalize_params()
    |> change_mission()
    |> calculate()
  end

  @doc """
  Costs a mission from an already-built changeset.

  Invalid changesets come back as `{:error, changeset}` rather than a total,
  which is what lets the LiveView clear a stale result instead of showing a
  number that no longer matches the form.
  """
  @spec calculate(Changeset.t()) :: {:ok, Fuel.result()} | {:error, Changeset.t() | Fuel.error()}
  def calculate(%Changeset{} = changeset) do
    with {:ok, mission} <- Changeset.apply_action(changeset, :validate) do
      Fuel.breakdown(mission.mass, mission.steps)
    end
  end

  @doc "Builds a mission changeset from form params."
  @spec change_mission(params()) :: Changeset.t()
  def change_mission(params \\ %{}), do: Mission.changeset(%Mission{}, params)

  @doc """
  Normalises form params into a stable shape.

  `inputs_for` submits embeds as an index-keyed map (`%{"0" => …, "1" => …}`)
  while presets and step add/remove work with a plain list. Everything
  downstream sees a list, ordered by index.
  """
  @spec normalize_params(params()) :: params()
  def normalize_params(params) do
    params
    |> Map.put_new("mass", "")
    |> Map.update("steps", [], &normalize_steps/1)
  end

  defp normalize_steps(steps) when is_list(steps), do: steps

  defp normalize_steps(steps) when is_map(steps) do
    steps
    |> Enum.sort_by(fn {index, _step} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, step} -> step end)
  end

  defp normalize_steps(_steps), do: []

  @doc "Params for an empty mission with a single blank step."
  @spec blank_params() :: params()
  def blank_params, do: %{"mass" => "", "steps" => [blank_step_params()]}

  @doc "Params for a single blank step. See `blank_params/0`."
  @spec blank_step_params() :: params()
  def blank_step_params, do: %{"action" => "", "planet" => ""}

  @doc "The example missions from the mission brief."
  @spec presets() :: [map()]
  def presets, do: @presets

  @doc """
  Form params for a named preset, falling back to a blank mission.

  ## Examples

      iex> NasaFuel.Flight.preset_params("mars_mission")["mass"]
      "14606"

  """
  @spec preset_params(String.t()) :: params()
  def preset_params(id) do
    case preset(id) do
      nil -> blank_params()
      preset -> %{"mass" => to_string(preset.mass), "steps" => step_params(preset.path)}
    end
  end

  @doc "The preset with the given id, or `nil` when there is no such preset."
  @spec preset(String.t()) :: map() | nil
  def preset(id), do: Enum.find(@presets, &(&1.id == id))

  defp step_params(path) do
    Enum.map(path, fn {action, planet} ->
      %{"action" => to_string(action), "planet" => to_string(planet)}
    end)
  end

  defdelegate planet_options(), to: Planet, as: :options
  defdelegate planet_label(planet), to: Planet, as: :label
  defdelegate action_options(), to: Step, as: :action_options
  defdelegate action_label(action), to: Step, as: :label
end
