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

    test "rejects launching twice without landing in between" do
      attrs =
        valid_attrs(%{
          "steps" => [
            %{"action" => "launch", "planet" => "earth"},
            %{"action" => "launch", "planet" => "moon"}
          ]
        })

      assert %{steps: ["cannot launch twice without landing in between"]} =
               attrs |> changeset() |> errors_on()
    end

    test "rejects landing twice without launching in between" do
      attrs =
        valid_attrs(%{
          "steps" => [
            %{"action" => "land", "planet" => "moon"},
            %{"action" => "land", "planet" => "mars"}
          ]
        })

      assert %{steps: ["cannot land twice without launching in between"]} =
               attrs |> changeset() |> errors_on()
    end

    test "rejects launching from a planet it never landed on" do
      attrs =
        valid_attrs(%{
          "steps" => [
            %{"action" => "launch", "planet" => "earth"},
            %{"action" => "land", "planet" => "moon"},
            %{"action" => "launch", "planet" => "mars"}
          ]
        })

      assert %{steps: ["must launch from the planet it last landed on"]} =
               attrs |> changeset() |> errors_on()
    end

    test "accepts launching from the planet it just landed on" do
      attrs =
        valid_attrs(%{
          "steps" => [
            %{"action" => "launch", "planet" => "earth"},
            %{"action" => "land", "planet" => "moon"},
            %{"action" => "launch", "planet" => "moon"},
            %{"action" => "land", "planet" => "earth"}
          ]
        })

      assert changeset(attrs).valid?
    end

    test "accepts a path that opens with a landing" do
      # The brief costs landing Apollo 11 on Earth as a mission on its own, so
      # requiring a launch first would reject an example from the spec.
      attrs = valid_attrs(%{"steps" => [%{"action" => "land", "planet" => "earth"}]})

      assert changeset(attrs).valid?
    end

    test "holds continuity errors until every step is complete" do
      # Mid-edit the second step has no planet yet. It already says "can't be
      # blank"; a continuity complaint about a path it cannot form is noise.
      attrs =
        valid_attrs(%{
          "steps" => [
            %{"action" => "launch", "planet" => "earth"},
            %{"action" => "launch", "planet" => ""}
          ]
        })

      changeset = changeset(attrs)

      assert %{steps: [%{}, %{planet: ["can't be blank"]}]} = errors_on(changeset)
      assert changeset.errors == []
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
