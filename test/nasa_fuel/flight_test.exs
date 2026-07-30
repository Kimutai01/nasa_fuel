defmodule NasaFuel.FlightTest do
  use ExUnit.Case, async: true

  import NasaFuel.ChangesetHelpers

  alias NasaFuel.Flight

  doctest NasaFuel.Flight

  describe "plan/1" do
    test "costs a valid mission" do
      params = %{
        "mass" => "28801",
        "steps" => [
          %{"action" => "launch", "planet" => "earth"},
          %{"action" => "land", "planet" => "moon"},
          %{"action" => "launch", "planet" => "moon"},
          %{"action" => "land", "planet" => "earth"}
        ]
      }

      assert {:ok, %{total: 51_898}} = Flight.plan(params)
    end

    test "accepts the index-keyed steps a form submits" do
      params = %{
        "mass" => "28801",
        "steps" => %{
          "0" => %{"action" => "launch", "planet" => "earth"},
          "1" => %{"action" => "land", "planet" => "moon"}
        }
      }

      assert {:ok, result} = Flight.plan(params)
      assert Enum.map(result.steps, & &1.planet) == [:earth, :moon]
    end

    test "returns a changeset instead of a total when the mission is invalid" do
      params = %{"mass" => "0", "steps" => [%{"action" => "land", "planet" => "earth"}]}

      assert {:error, %Ecto.Changeset{} = changeset} = Flight.plan(params)
      assert %{mass: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "an invalid step never reaches the calculator" do
      params = %{"mass" => "28801", "steps" => [%{"action" => "land", "planet" => "pluto"}]}

      assert {:error, %Ecto.Changeset{}} = Flight.plan(params)
    end
  end

  describe "presets" do
    test "every preset matches the total published in the mission brief" do
      expected = %{
        "apollo_11" => 51_898,
        "mars_mission" => 33_388,
        "passenger_ship" => 212_161
      }

      for %{id: id} <- Flight.presets() do
        assert {:ok, %{total: total}} = id |> Flight.preset_params() |> Flight.plan()
        assert total == expected[id], "#{id} totalled #{total}, expected #{expected[id]}"
      end
    end

    test "every preset is itself valid input" do
      for %{id: id} <- Flight.presets() do
        assert id |> Flight.preset_params() |> Flight.change_mission() |> Map.fetch!(:valid?)
      end
    end

    test "an unknown preset falls back to a blank mission" do
      assert Flight.preset_params("voyager") == Flight.blank_params()
    end
  end

  describe "blank_params/0" do
    test "is an empty mission with a single blank step to fill in" do
      assert Flight.blank_params() == %{
               "mass" => "",
               "steps" => [%{"action" => "", "planet" => ""}]
             }
    end

    test "is invalid — a blank mission is never costed" do
      assert {:error, %Ecto.Changeset{valid?: false}} = Flight.plan(Flight.blank_params())
    end

    test "the client's untouched-field markers never reach the calculator" do
      params = %{
        "mass" => "28801",
        "_unused_mass" => "",
        "steps" => [%{"action" => "land", "planet" => "earth", "_unused_planet" => ""}]
      }

      assert {:ok, %{total: 13_447}} = Flight.plan(params)
    end
  end

  describe "normalize_params/1" do
    test "orders index-keyed steps numerically, not as strings" do
      steps =
        Map.new(0..10, fn index ->
          {to_string(index), %{"action" => "land", "planet" => "earth", "n" => index}}
        end)

      normalized = Flight.normalize_params(%{"mass" => "1", "steps" => steps})

      assert Enum.map(normalized["steps"], & &1["n"]) == Enum.to_list(0..10)
    end

    test "leaves a list of steps alone" do
      steps = [%{"action" => "land", "planet" => "earth"}]

      assert Flight.normalize_params(%{"mass" => "1", "steps" => steps})["steps"] == steps
    end

    test "fills in missing keys" do
      assert Flight.normalize_params(%{}) == %{"mass" => "", "steps" => []}
    end
  end

  describe "form options" do
    test "planets are offered as label and value pairs" do
      assert Flight.planet_options() == [{"Earth", :earth}, {"Moon", :moon}, {"Mars", :mars}]
    end

    test "actions are offered as label and value pairs" do
      assert Flight.action_options() == [{"Launch", :launch}, {"Land", :land}]
    end
  end
end
