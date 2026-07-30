defmodule NasaFuel.Flight.MissionTest do
  use ExUnit.Case, async: true

  import NasaFuel.ChangesetHelpers

  alias NasaFuel.Flight.Mission

  defp changeset(attrs), do: Mission.changeset(%Mission{}, attrs)

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{"mass" => "28801", "steps" => [%{"action" => "land", "planet" => "earth"}]},
      overrides
    )
  end

  describe "mass" do
    test "accepts a positive integer" do
      assert %{valid?: true} = changeset = changeset(valid_attrs())
      assert Ecto.Changeset.get_change(changeset, :mass) == 28_801
    end

    test "is required" do
      assert %{mass: ["can't be blank"]} =
               valid_attrs(%{"mass" => ""}) |> changeset() |> errors_on()
    end

    test "rejects zero" do
      assert %{mass: ["must be greater than 0"]} =
               valid_attrs(%{"mass" => "0"}) |> changeset() |> errors_on()
    end

    test "rejects a negative mass" do
      assert %{mass: ["must be greater than 0"]} =
               valid_attrs(%{"mass" => "-28801"}) |> changeset() |> errors_on()
    end

    test "rejects text" do
      assert %{mass: ["is invalid"]} =
               valid_attrs(%{"mass" => "heavy"}) |> changeset() |> errors_on()
    end

    test "rejects trailing garbage rather than silently truncating it" do
      # Integer.parse/1 would happily return 12 here
      assert %{mass: ["is invalid"]} =
               valid_attrs(%{"mass" => "12abc"}) |> changeset() |> errors_on()
    end

    test "rejects a fractional mass" do
      assert %{mass: ["is invalid"]} =
               valid_attrs(%{"mass" => "28801.5"}) |> changeset() |> errors_on()
    end
  end

  describe "steps" do
    test "requires at least one step" do
      assert %{steps: ["can't be blank"]} =
               valid_attrs(%{"steps" => []}) |> changeset() |> errors_on()
    end

    test "requires an action" do
      attrs = valid_attrs(%{"steps" => [%{"action" => "", "planet" => "earth"}]})

      assert %{steps: [%{action: ["can't be blank"]}]} = attrs |> changeset() |> errors_on()
    end

    test "requires a planet" do
      attrs = valid_attrs(%{"steps" => [%{"action" => "land", "planet" => ""}]})

      assert %{steps: [%{planet: ["can't be blank"]}]} = attrs |> changeset() |> errors_on()
    end

    test "rejects an unsupported planet" do
      attrs = valid_attrs(%{"steps" => [%{"action" => "land", "planet" => "pluto"}]})

      assert %{steps: [%{planet: ["is invalid"]}]} = attrs |> changeset() |> errors_on()
    end

    test "rejects an unsupported action" do
      attrs = valid_attrs(%{"steps" => [%{"action" => "hover", "planet" => "earth"}]})

      assert %{steps: [%{action: ["is invalid"]}]} = attrs |> changeset() |> errors_on()
    end

    test "reports errors per step, keeping valid siblings clean" do
      attrs =
        valid_attrs(%{
          "steps" => [
            %{"action" => "launch", "planet" => "earth"},
            %{"action" => "land", "planet" => ""}
          ]
        })

      assert %{steps: [%{}, %{planet: ["can't be blank"]}]} = attrs |> changeset() |> errors_on()
    end

    test "casts strings into atoms so the calculator receives domain values" do
      attrs =
        valid_attrs(%{
          "steps" => [
            %{"action" => "launch", "planet" => "earth"},
            %{"action" => "land", "planet" => "moon"}
          ]
        })

      assert {:ok, mission} = attrs |> changeset() |> Ecto.Changeset.apply_action(:validate)

      assert Enum.map(mission.steps, &{&1.action, &1.planet}) == [
               {:launch, :earth},
               {:land, :moon}
             ]
    end

    test "one invalid step invalidates the whole mission" do
      attrs =
        valid_attrs(%{
          "steps" => [
            %{"action" => "launch", "planet" => "earth"},
            %{"action" => "land", "planet" => "pluto"}
          ]
        })

      refute changeset(attrs).valid?
    end
  end
end
