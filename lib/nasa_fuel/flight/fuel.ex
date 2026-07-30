defmodule NasaFuel.Flight.Fuel do
  @moduledoc """
  Fuel arithmetic for a flight path.

  A single manoeuvre burns `mass * gravity * factor - constant`, rounded down.
  That fuel is itself mass the ship has to carry, so the formula is reapplied to
  each result and the results summed, until an application stops being positive.

  A flight path is folded **last step first**. Fuel burned late in a mission has
  to be lifted off the ground by every step before it, so each step is measured
  against the dry mass plus all fuel accrued after it. Folding forwards instead
  silently under-reports the total.

  The compounding terminates because `gravity * factor < 1` for every supported
  planet, so each application yields strictly less than the last. A body with
  gravity above ~23.8 m/s² would not converge; none are supported.

  Nothing here knows about Ecto or the web layer — a step is any map carrying
  `:action` and `:planet`.
  """

  alias NasaFuel.Flight.Planet
  alias NasaFuel.Flight.Step

  # action => {factor, constant}
  @coefficients %{launch: {0.042, 33}, land: {0.033, 42}}

  @type step :: %{:action => Step.action(), :planet => Planet.t(), optional(any()) => any()}

  @type entry :: %{
          action: Step.action(),
          planet: Planet.t(),
          mass: pos_integer(),
          fuel: non_neg_integer()
        }

  @type result :: %{total: non_neg_integer(), steps: [entry()]}

  @type error :: {:unknown_planet, any()} | {:unknown_action, any()} | {:invalid_step, any()}

  @doc """
  Fuel for each step plus the mission total.

  Steps are given and returned in flight order, though they are calculated in
  reverse. Each returned entry carries the `:mass` it was calculated against —
  the dry mass plus fuel for every later step — which is what makes the reverse
  fold visible in the UI.

  An empty flight path needs no fuel and returns a total of `0`.
  """
  @spec breakdown(pos_integer(), [step()]) :: {:ok, result()} | {:error, error()}
  def breakdown(mass, steps) when is_integer(mass) and mass > 0 and is_list(steps) do
    steps
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, 0, []}, fn step, {:ok, total, entries} ->
      case entry(mass + total, step) do
        {:ok, entry} -> {:cont, {:ok, total + entry.fuel, [entry | entries]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, total, entries} -> {:ok, %{total: total, steps: entries}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Total fuel for a flight path. See `breakdown/2`."
  @spec total(pos_integer(), [step()]) :: {:ok, non_neg_integer()} | {:error, error()}
  def total(mass, steps) do
    with {:ok, %{total: total}} <- breakdown(mass, steps), do: {:ok, total}
  end

  defp entry(mass, %{action: action, planet: planet}) do
    with {:ok, gravity} <- fetch_gravity(planet),
         {:ok, coefficients} <- fetch_coefficients(action) do
      {:ok,
       %{action: action, planet: planet, mass: mass, fuel: compound(mass, gravity, coefficients)}}
    end
  end

  defp entry(_mass, step), do: {:error, {:invalid_step, step}}

  defp fetch_gravity(planet) do
    case Planet.gravity(planet) do
      {:ok, gravity} -> {:ok, gravity}
      :error -> {:error, {:unknown_planet, planet}}
    end
  end

  defp fetch_coefficients(action) do
    case Map.fetch(@coefficients, action) do
      {:ok, coefficients} -> {:ok, coefficients}
      :error -> {:error, {:unknown_action, action}}
    end
  end

  defp compound(mass, gravity, coefficients) do
    mass
    |> apply_formula(gravity, coefficients)
    |> compound(gravity, coefficients, 0)
  end

  defp compound(fuel, _gravity, _coefficients, total) when fuel <= 0, do: total

  defp compound(fuel, gravity, coefficients, total) do
    fuel
    |> apply_formula(gravity, coefficients)
    |> compound(gravity, coefficients, total + fuel)
  end

  defp apply_formula(mass, gravity, {factor, constant}) do
    floor(mass * gravity * factor - constant)
  end
end
