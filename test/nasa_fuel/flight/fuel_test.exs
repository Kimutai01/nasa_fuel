defmodule NasaFuel.Flight.FuelTest do
  use ExUnit.Case, async: true

  alias NasaFuel.Flight.Fuel

  defp launch(planet), do: %{action: :launch, planet: planet}
  defp land(planet), do: %{action: :land, planet: planet}

  describe "total/2 against the mission briefs" do
    test "Apollo 11" do
      path = [launch(:earth), land(:moon), launch(:moon), land(:earth)]

      assert Fuel.total(28_801, path) == {:ok, 51_898}
    end

    test "Mars mission" do
      path = [launch(:earth), land(:mars), launch(:mars), land(:earth)]

      assert Fuel.total(14_606, path) == {:ok, 33_388}
    end

    test "passenger ship" do
      path = [
        launch(:earth),
        land(:moon),
        launch(:moon),
        land(:mars),
        launch(:mars),
        land(:earth)
      ]

      assert Fuel.total(75_432, path) == {:ok, 212_161}
    end
  end

  describe "total/2 compounding" do
    test "fuel is itself fuelled until an application stops being positive" do
      # 9278 + 2960 + 915 + 254 + 40, the worked example from the brief
      assert Fuel.total(28_801, [land(:earth)]) == {:ok, 13_447}
    end

    test "compounding halts on an application that floors to zero" do
      # The chain runs 11689, 4781, 1936, 764, 281, 82 and then stops:
      # 82 * 9.807 * 0.042 - 33 = 0.775, which floors to 0.
      assert Fuel.total(28_461, [launch(:earth)]) == {:ok, 19_533}
    end

    test "a first application that floors to zero needs no fuel at all" do
      assert Fuel.total(82, [launch(:earth)]) == {:ok, 0}
    end

    test "a negative application needs no fuel rather than refunding any" do
      # 1 * 1.62 * 0.033 - 42 is about -41.9
      assert Fuel.total(1, [land(:moon)]) == {:ok, 0}
    end

    test "handles a mass far larger than any real spacecraft" do
      assert {:ok, total} = Fuel.total(1_000_000_000, [launch(:earth)])
      assert is_integer(total) and total > 0
    end
  end

  describe "total/2 path handling" do
    test "an empty flight path needs no fuel" do
      assert Fuel.total(28_801, []) == {:ok, 0}
    end

    test "later steps are fuelled by earlier ones, so order changes the total" do
      forwards = Fuel.total(28_801, [launch(:earth), land(:moon)])
      backwards = Fuel.total(28_801, [land(:moon), launch(:earth)])

      refute forwards == backwards
    end

    test "each step costs at least what it would cost alone" do
      # Launching from Earth first means also lifting the fuel for the Moon landing.
      assert {:ok, alone} = Fuel.total(28_801, [launch(:earth)])
      assert {:ok, carrying} = Fuel.total(28_801, [launch(:earth), land(:moon)])

      assert carrying > alone
    end
  end

  describe "breakdown/2" do
    test "returns steps in flight order even though they are costed in reverse" do
      path = [launch(:earth), land(:moon), launch(:moon), land(:earth)]

      assert {:ok, result} = Fuel.breakdown(28_801, path)

      assert Enum.map(result.steps, &{&1.action, &1.planet}) == [
               {:launch, :earth},
               {:land, :moon},
               {:launch, :moon},
               {:land, :earth}
             ]
    end

    test "each step is costed against the dry mass plus fuel for every later step" do
      path = [launch(:earth), land(:moon), launch(:moon), land(:earth)]

      assert {:ok, result} = Fuel.breakdown(28_801, path)

      assert Enum.map(result.steps, & &1.mass) == [47_711, 45_249, 42_248, 28_801]
      assert Enum.map(result.steps, & &1.fuel) == [32_988, 2_462, 3_001, 13_447]
    end

    test "the last step is costed against the bare dry mass" do
      assert {:ok, result} = Fuel.breakdown(28_801, [launch(:earth), land(:earth)])

      assert List.last(result.steps).mass == 28_801
    end

    test "step fuel sums to the total" do
      path = [launch(:earth), land(:mars), launch(:mars), land(:earth)]

      assert {:ok, result} = Fuel.breakdown(14_606, path)

      assert result.steps |> Enum.map(& &1.fuel) |> Enum.sum() == result.total
    end
  end

  describe "total/2 rejects unusable input" do
    test "an unsupported planet" do
      assert Fuel.total(28_801, [land(:pluto)]) == {:error, {:unknown_planet, :pluto}}
    end

    test "an unsupported action" do
      assert Fuel.total(28_801, [%{action: :hover, planet: :earth}]) ==
               {:error, {:unknown_action, :hover}}
    end

    test "a step missing its keys" do
      assert Fuel.total(28_801, [%{}]) == {:error, {:invalid_step, %{}}}
    end

    test "the first bad step short-circuits the rest of the path" do
      assert Fuel.total(28_801, [land(:pluto), land(:vulcan)]) ==
               {:error, {:unknown_planet, :vulcan}}
    end

    test "a non-positive mass never reaches the calculator" do
      assert_raise FunctionClauseError, fn -> Fuel.total(0, [land(:earth)]) end
      assert_raise FunctionClauseError, fn -> Fuel.total(-1, [land(:earth)]) end
    end
  end
end
