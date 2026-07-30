defmodule NasaFuelWeb.MissionLive do
  @moduledoc """
  Interactive flight planner.

  The raw form params are the single source of truth. Every event rebuilds the
  changeset from params and recosts the mission, so the total on screen can
  never drift from the path on screen — an invalid mission clears the result
  rather than leaving a stale number behind.
  """

  use NasaFuelWeb, :live_view

  alias NasaFuel.Flight

  @default_preset "apollo_11"

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Flight planner")
      |> assign(:result, nil)
      |> assign(:preset, @default_preset)
      |> assign_mission(seed_preset(@default_preset))

    {:ok, if(connected?(socket), do: recalculate(socket), else: socket)}
  end

  @impl true
  def handle_event("validate", %{"mission" => params}, socket) do
    {:noreply, socket |> hand_edited() |> assign_mission(params) |> recalculate()}
  end

  def handle_event("add_step", _params, socket) do
    {:noreply, socket |> hand_edited() |> update_steps(&(&1 ++ [seed_step()]))}
  end

  def handle_event("remove_step", %{"index" => index}, socket) do
    case Integer.parse(index) do
      {index, ""} when index >= 0 ->
        {:noreply, socket |> hand_edited() |> update_steps(&List.delete_at(&1, index))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("load_preset", %{"preset" => id}, socket) do
    # An id with no matching preset seeds a blank mission, so nothing is loaded.
    socket = assign(socket, :preset, if(Flight.preset(id), do: id))

    {:noreply, socket |> assign_mission(seed_preset(id)) |> recalculate()}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, socket |> hand_edited() |> assign_mission(seed_blank()) |> recalculate()}
  end

  # Once the mission is touched by hand it is no longer the preset that seeded
  # it, so nothing stays highlighted as loaded.
  defp hand_edited(socket), do: assign(socket, :preset, nil)

  # The `seed_*` helpers wrap `Flight`'s params builders for use as form state.
  defp seed_preset(id), do: id |> Flight.preset_params() |> mark_mission_unused()

  defp seed_blank, do: Flight.blank_params() |> mark_mission_unused()

  defp seed_step, do: Flight.blank_step_params() |> mark_unused()

  # LiveView's client submits a companion `_unused_<field>` param for every input
  # the user has not interacted with, which is what `used_input?/1` reads to keep
  # errors hidden until they are earned. Params built by the `seed_*` helpers
  # above — clearing the form, adding a step, loading a preset — have no client to
  # do that for them, so every blank field they carry is marked on the way in.
  # Without this, a fresh blank step renders "can't be blank" against a field
  # nobody has reached yet. A preset fills every field, so marking is a no-op.
  #
  # This suppresses error *display* only. A blank mission is still invalid, so the
  # result stays cleared and the pending hint explains what is missing.
  defp mark_mission_unused(%{"steps" => steps} = params) do
    params
    |> Map.put("steps", Enum.map(steps, &mark_unused/1))
    |> mark_unused()
  end

  defp mark_unused(fields) do
    for {field, ""} <- fields, reduce: fields do
      marked -> Map.put(marked, "_unused_#{field}", "")
    end
  end

  defp update_steps(socket, fun) do
    params = Map.update!(socket.assigns.params, "steps", fun)

    socket |> assign_mission(params) |> recalculate()
  end

  defp assign_mission(socket, params) do
    params = Flight.normalize_params(params)
    form = params |> Flight.change_mission() |> to_form(as: :mission, action: :validate)

    socket
    |> assign(:params, params)
    |> assign(:form, form)
  end

  defp recalculate(socket) do
    case Flight.calculate(socket.assigns.form.source) do
      {:ok, result} -> assign(socket, :result, result)
      {:error, _reason} -> assign(socket, :result, nil)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-14">
        <div class="grid gap-10 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-start lg:gap-14">
          <div class="space-y-8">
            <header class="space-y-3">
              <p class="text-xs font-medium uppercase tracking-[0.18em] text-primary">
                Flight planner
              </p>
              <h1 class="text-4xl font-light leading-tight tracking-tight sm:text-5xl">
                How much fuel does the mission need?
              </h1>
              <p class="max-w-xl text-base-content/60">
                Fuel is cargo. Every manoeuvre has to lift the fuel for every manoeuvre that
                comes after it, so the cost of a flight path accumulates backwards from the
                last step to the first.
              </p>
            </header>

            <section id="mission-presets" class="flex flex-wrap items-center gap-2">
              <span class="mr-1 text-xs font-medium uppercase tracking-[0.14em] text-base-content/40">
                Load example
              </span>
              <button
                :for={preset <- Flight.presets()}
                id={"preset-#{preset.id}"}
                type="button"
                aria-pressed={to_string(@preset == preset.id)}
                class={[
                  "flex items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm transition-colors",
                  "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary motion-reduce:transition-none",
                  if(@preset == preset.id,
                    do: "border-primary bg-primary font-medium text-primary-content",
                    else: "border-base-300 hover:border-primary hover:text-primary"
                  )
                ]}
                phx-click="load_preset"
                phx-value-preset={preset.id}
              >
                <.icon :if={@preset == preset.id} name="hero-check-micro" class="size-3.5" />
                {preset.name}
              </button>
              <button
                id="clear-mission"
                type="button"
                class="px-2 py-1.5 text-sm text-base-content/40 transition-colors hover:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary motion-reduce:transition-none"
                phx-click="clear"
              >
                Clear
              </button>
            </section>

            <.form
              for={@form}
              id="mission-form"
              phx-change="validate"
              phx-submit="validate"
              class="space-y-8"
            >
              <div class="max-w-xs">
                <.input
                  field={@form[:mass]}
                  type="number"
                  label="Spacecraft mass (kg)"
                  min="1"
                  step="1"
                  placeholder="28801"
                />
              </div>

              <fieldset class="space-y-4">
                <legend class="mb-3 text-xs font-medium uppercase tracking-[0.14em] text-base-content/40">
                  Flight path
                </legend>

                <div class="relative space-y-2.5">
                  <div
                    :if={length(@params["steps"]) > 1}
                    class="absolute inset-y-4 left-[0.9375rem] w-px bg-base-300"
                    aria-hidden="true"
                  >
                  </div>

                  <.inputs_for :let={step} field={@form[:steps]}>
                    <div id={"step-#{step.index}"} class="group relative flex items-start gap-3">
                      <span class="z-10 mt-2.5 flex size-8 shrink-0 items-center justify-center rounded-full border border-base-300 bg-base-100 text-xs font-medium tabular-nums text-base-content/50">
                        {step.index + 1}
                      </span>
                      <div class="flex-1">
                        <.input
                          field={step[:action]}
                          type="select"
                          prompt="Action"
                          options={Flight.action_options()}
                        />
                      </div>
                      <div class="flex-1">
                        <.input
                          field={step[:planet]}
                          type="select"
                          prompt="Planet"
                          options={Flight.planet_options()}
                        />
                      </div>
                      <%!-- Revealed on hover, but only where a pointer can hover.
                      `group-hover` never fires on a touchscreen, so hiding by
                      default there would make the control unreachable. --%>
                      <button
                        id={"remove-step-#{step.index}"}
                        type="button"
                        class="mt-2.5 flex size-8 shrink-0 items-center justify-center rounded-lg text-base-content/30 opacity-100 transition-all hover:bg-error/10 hover:text-error focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-error motion-reduce:transition-none pointer-fine:opacity-0 pointer-fine:focus-visible:opacity-100 pointer-fine:group-hover:opacity-100"
                        phx-click="remove_step"
                        phx-value-index={step.index}
                        aria-label={"Remove step #{step.index + 1}"}
                      >
                        <.icon name="hero-x-mark" class="size-4" />
                      </button>
                    </div>
                  </.inputs_for>
                </div>

                <div :if={@form[:steps].errors != []} id="steps-error" class="text-sm text-error">
                  <p :for={message <- Enum.map(@form[:steps].errors, &translate_error/1)}>
                    A flight path {message}
                  </p>
                </div>

                <button
                  id="add-step"
                  type="button"
                  class="flex items-center gap-1.5 rounded-lg px-2 py-1.5 text-sm font-medium text-primary transition-colors hover:bg-primary/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary motion-reduce:transition-none"
                  phx-click="add_step"
                >
                  <.icon name="hero-plus-mini" class="size-4" /> Add manoeuvre
                </button>
              </fieldset>
            </.form>
          </div>

          <.total_panel result={@result} />
        </div>

        <.breakdown_panel result={@result} />
      </div>
    </Layouts.app>
    """
  end

  attr :result, :map, default: nil

  defp total_panel(%{result: nil} = assigns) do
    ~H"""
    <aside
      id="mission-pending"
      class="rounded-2xl border border-dashed border-base-300 p-6 lg:sticky lg:top-20"
    >
      <p class="text-xs font-medium uppercase tracking-[0.14em] text-base-content/40">
        Total fuel needed
      </p>
      <p class="mt-2 text-5xl font-light tabular-nums text-base-content/20">&mdash;</p>
      <p class="mt-4 text-sm leading-relaxed text-base-content/50">
        Set a mass above zero and complete every manoeuvre to see the fuel this mission needs.
      </p>
    </aside>
    """
  end

  defp total_panel(assigns) do
    ~H"""
    <aside
      id="mission-result"
      class="rounded-2xl border border-base-300 bg-base-200/60 p-6 lg:sticky lg:top-20"
    >
      <p class="text-xs font-medium uppercase tracking-[0.14em] text-base-content/40">
        Total fuel needed
      </p>
      <p class="mt-1.5 flex items-baseline gap-2">
        <span id="mission-total" class="text-5xl font-light tabular-nums tracking-tight">
          {format(@result.total)}
        </span>
        <span class="text-lg font-light text-base-content/40">kg</span>
      </p>

      <dl class="mt-5 space-y-2 border-t border-base-300 pt-4 text-sm">
        <div class="flex items-baseline justify-between gap-3">
          <dt class="text-base-content/50">Spacecraft</dt>
          <dd id="mission-dry-mass" class="tabular-nums">{format(@result.mass)} kg</dd>
        </div>
        <div class="flex items-baseline justify-between gap-3">
          <dt class="text-base-content/50">Manoeuvres</dt>
          <dd class="tabular-nums">{length(@result.steps)}</dd>
        </div>
        <div class="flex items-baseline justify-between gap-3">
          <dt class="text-base-content/50">Route</dt>
          <dd class="text-right">{route(@result.steps)}</dd>
        </div>
      </dl>
    </aside>
    """
  end

  attr :result, :map, default: nil

  defp breakdown_panel(%{result: nil} = assigns), do: ~H""

  defp breakdown_panel(assigns) do
    assigns = assign(assigns, :heaviest, heaviest(assigns.result.steps))

    ~H"""
    <section class="space-y-4">
      <div>
        <h2 class="text-xs font-medium uppercase tracking-[0.14em] text-base-content/40">
          Manoeuvre by manoeuvre
        </h2>
        <p class="mt-2 max-w-2xl text-sm text-base-content/60">
          Read it bottom to top. The last manoeuvre lifts the bare spacecraft; every manoeuvre
          before it also lifts the fuel for everything that follows, which is why the first one
          costs the most.
        </p>
      </div>

      <div class="overflow-x-auto">
        <table id="mission-breakdown" class="w-full min-w-lg text-sm">
          <thead>
            <tr class="border-b border-base-300 text-left align-bottom text-xs uppercase tracking-[0.1em] text-base-content/40">
              <th class="w-10 pb-2 font-medium">#</th>
              <th class="pb-2 font-medium">Manoeuvre</th>
              <th class="pb-2 pl-6 text-right font-medium">Fuel burned</th>
              <th class="w-1/3 pb-2 pl-8 font-medium">Mass it has to lift</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={{step, index} <- Enum.with_index(@result.steps)}
              id={"breakdown-#{index}"}
              class="border-b border-base-300/40"
            >
              <td class="py-3 tabular-nums text-base-content/30">{index + 1}</td>
              <td class="py-3">
                <span class="font-medium">{Flight.action_label(step.action)}</span>
                <span class="text-base-content/30">&middot;</span>
                <span>{Flight.planet_label(step.planet)}</span>
              </td>
              <td id={"breakdown-#{index}-fuel"} class="py-3 pl-6 text-right tabular-nums">
                <span class="font-medium">{format(step.fuel)}</span>
                <span class="text-xs text-base-content/40">kg</span>
              </td>
              <td class="py-3 pl-8">
                <div class="flex items-center gap-3">
                  <div class="h-1.5 min-w-16 flex-1 overflow-hidden rounded-full bg-base-300">
                    <div
                      class="h-full rounded-full bg-primary/50"
                      style={"width: #{share(step.mass, @heaviest)}%"}
                    >
                    </div>
                  </div>
                  <span
                    id={"breakdown-#{index}-mass"}
                    class="shrink-0 tabular-nums text-base-content/50"
                  >
                    {format(step.mass)}
                    <span class="text-xs text-base-content/40">kg</span>
                  </span>
                </div>
              </td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="text-base-content/50">
              <td></td>
              <td class="pt-3 text-xs uppercase tracking-[0.1em]">Total fuel</td>
              <td class="pt-3 pl-6 text-right tabular-nums">
                <span class="font-medium text-base-content">{format(@result.total)}</span>
                <span class="text-xs">kg</span>
              </td>
              <td></td>
            </tr>
          </tfoot>
        </table>
      </div>
    </section>
    """
  end

  defp heaviest(steps), do: steps |> Enum.map(& &1.mass) |> Enum.max(&>=/2, fn -> 1 end)

  defp share(mass, heaviest), do: Float.round(mass / heaviest * 100, 1)

  defp route(steps) do
    steps
    |> Enum.map(& &1.planet)
    |> Enum.dedup()
    |> Enum.map_join(" → ", &Flight.planet_label/1)
  end

  defp format(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
