defmodule NasaFuelWeb.MissionLiveTest do
  use NasaFuelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  defp step_row(index), do: "#step-#{index}"
  defp step_input(index, field), do: "select[name='mission[steps][#{index}][#{field}]']"

  # Step rows are indexed contiguously from 0: the last one exists, the next does not.
  defp assert_step_count(view, count) do
    if count > 0, do: assert(has_element?(view, step_row(count - 1)))
    refute has_element?(view, step_row(count))
  end

  defp total?(view, formatted), do: has_element?(view, "#mission-total", formatted)
  defp costed?(view), do: has_element?(view, "#mission-result")
  defp pending?(view), do: has_element?(view, "#mission-pending")

  defp error?(view, message), do: has_element?(view, "#mission-form", message)

  defp loaded?(view, preset), do: has_element?(view, "#preset-#{preset}[aria-pressed='true']")

  describe "mount" do
    test "the dead render builds the form but skips the calculation", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      # No LiveView to query on a dead render, so this is the one place that
      # inspects the markup directly.
      assert html =~ ~s(id="mission-form")
      assert html =~ ~s(id="mission-pending")
      refute html =~ ~s(id="mission-result")
    end

    test "the connected mount costs the default mission", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert costed?(view)
      assert total?(view, "51,898")
    end

    test "renders one breakdown row per manoeuvre, in flight order", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#breakdown-0", "Launch")
      assert has_element?(view, "#breakdown-1", "Land")
      assert has_element?(view, "#breakdown-2", "Launch")
      assert has_element?(view, "#breakdown-3", "Land")
      refute has_element?(view, "#breakdown-4")
    end

    test "the first manoeuvre carries the fuel for every later one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Launching from Earth lifts the whole mission: 47,711 kg costing 32,988 kg.
      assert has_element?(view, "#breakdown-0-mass", "47,711")
      assert has_element?(view, "#breakdown-0-fuel", "32,988")

      # The last manoeuvre is costed against the bare dry mass.
      assert has_element?(view, "#breakdown-3-mass", "28,801")
    end
  end

  describe "editing the mission" do
    test "recosts the mission when the mass changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert total?(view, "51,898")

      view |> form("#mission-form", mission: %{mass: "14606"}) |> render_change()

      assert costed?(view)
      refute total?(view, "51,898")
    end

    test "clears the result and reports the error when the mass is not positive", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#mission-form", mission: %{mass: "0"}) |> render_change()

      assert error?(view, "must be greater than 0")
      refute costed?(view)
      assert pending?(view)
    end

    test "clears the result when the mass is not a number", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#mission-form", mission: %{mass: "12abc"}) |> render_change()

      assert error?(view, "is invalid")
      refute costed?(view)
    end

    test "clears the result when a step is incomplete", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("#mission-form", mission: %{steps: %{"0" => %{planet: ""}}})
      |> render_change()

      assert error?(view, "can't be blank")
      refute costed?(view)
    end
  end

  describe "building the flight path" do
    test "adds a step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert_step_count(view, 4)

      view |> element("#add-step") |> render_click()

      assert_step_count(view, 5)
      assert has_element?(view, step_input(4, "action"))
    end

    test "an added step is incomplete, so the result is cleared until it is filled in", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#add-step") |> render_click()

      refute costed?(view)
      assert pending?(view)
    end

    test "removes a step and re-indexes the rest", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#remove-step-3") |> render_click()

      assert_step_count(view, 3)
      assert has_element?(view, step_input(2, "action"))
    end

    test "removing a step recosts the remaining path", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert total?(view, "51,898")

      view |> element("#remove-step-0") |> render_click()

      assert costed?(view)
      refute total?(view, "51,898")
    end

    test "removing every step reports that a flight path is required", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for _ <- 1..4, do: view |> element("#remove-step-0") |> render_click()

      assert_step_count(view, 0)
      assert has_element?(view, "#steps-error", "A flight path can't be blank")
      refute costed?(view)
    end
  end

  describe "a client-supplied step index is not trusted" do
    test "a negative index does not delete a step from the end", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_click(view, "remove_step", %{"index" => "-1"})

      # List.delete_at/2 reads -1 as the last element; every step must survive.
      assert_step_count(view, 4)
      assert total?(view, "51,898")
    end

    test "a malformed index is ignored rather than crashing the LiveView", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_click(view, "remove_step", %{"index" => "3abc"})

      assert_step_count(view, 4)
      assert total?(view, "51,898")
    end

    test "an out-of-range index leaves the path untouched", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_click(view, "remove_step", %{"index" => "99"})

      assert_step_count(view, 4)
      assert total?(view, "51,898")
    end
  end

  describe "errors are earned, not pre-emptive" do
    test "clearing the form does not flag the fields it just emptied", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#clear-mission") |> render_click()

      refute error?(view, "can't be blank")
    end

    test "a freshly added step is not flagged before it is filled in", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#add-step") |> render_click()

      refute error?(view, "can't be blank")
    end

    test "hiding the errors does not skip the validation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#clear-mission") |> render_click()

      # Quiet, but not accepted: no total, and the hint says what is missing.
      refute costed?(view)
      assert pending?(view)
    end

    test "a field the user empties themselves is still flagged", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#mission-form", mission: %{mass: ""}) |> render_change()

      assert error?(view, "can't be blank")
      refute costed?(view)
    end

    # `form/3 |> render_change/1` submits every field as touched, so it cannot
    # exercise the client's `_unused_` protocol. These params are raw, matching
    # what the JS client actually sends as the user works down the form.
    test "each field speaks up only once the user reaches it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#clear-mission") |> render_click()

      validate(view, "28801", %{"action" => "", "planet" => ""}, [:action, :planet])
      refute error?(view, "can't be blank")

      validate(view, "28801", %{"action" => "land", "planet" => ""}, [:planet])
      refute error?(view, "can't be blank")

      validate(view, "28801", %{"action" => "land", "planet" => ""}, [])
      assert error?(view, "can't be blank")

      validate(view, "28801", %{"action" => "land", "planet" => "earth"}, [])
      assert total?(view, "13,447")
    end
  end

  defp validate(view, mass, step, untouched) do
    step = Enum.reduce(untouched, step, &Map.put(&2, "_unused_#{&1}", ""))

    render_change(view, "validate", %{"mission" => %{"mass" => mass, "steps" => %{"0" => step}}})
  end

  describe "presets" do
    test "loads the Mars mission", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#preset-mars_mission") |> render_click()

      assert total?(view, "33,388")
    end

    test "loads the passenger ship", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#preset-passenger_ship") |> render_click()

      assert total?(view, "212,161")
      assert_step_count(view, 6)
    end

    test "an unknown preset falls back to a blank form, quietly", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_click(view, "load_preset", %{"preset" => "voyager"})

      refute costed?(view)
      refute error?(view, "can't be blank")
      assert pending?(view)
    end

    test "clearing empties the form and the result", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#clear-mission") |> render_click()

      refute costed?(view)
      assert pending?(view)
      assert_step_count(view, 1)
    end
  end

  describe "the loaded preset is shown as selected" do
    test "the mission the page opens with is marked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert loaded?(view, "apollo_11")
      refute loaded?(view, "mars_mission")
    end

    test "loading another preset moves the marker", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#preset-mars_mission") |> render_click()

      assert loaded?(view, "mars_mission")
      refute loaded?(view, "apollo_11")
    end

    test "editing the mass unmarks the preset it came from", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert loaded?(view, "apollo_11")

      view |> form("#mission-form", mission: %{mass: "28802"}) |> render_change()

      refute loaded?(view, "apollo_11")
    end

    test "editing the flight path unmarks the preset it came from", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#add-step") |> render_click()

      refute loaded?(view, "apollo_11")
    end

    test "removing a step unmarks the preset it came from", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#remove-step-0") |> render_click()

      refute loaded?(view, "apollo_11")
    end

    test "clearing leaves nothing marked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#clear-mission") |> render_click()

      refute loaded?(view, "apollo_11")
    end

    test "an unknown preset marks nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_click(view, "load_preset", %{"preset" => "voyager"})

      refute loaded?(view, "apollo_11")
    end
  end
end
