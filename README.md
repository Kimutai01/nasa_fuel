# NASA Fuel calculator

A Phoenix LiveView app that calculates the fuel required to fly a spacecraft
along an interplanetary flight path. Build a sequence of launches and landings,
enter a dry mass, and the total updates as you type.

The three scenarios from the brief are covered by tests and available as
one-click presets in the UI:

| Mission        | Path                                                       | Mass   | Fuel    |
| -------------- | ---------------------------------------------------------- | ------ | ------- |
| Apollo 11      | launch Earth, land Moon, launch Moon, land Earth            | 28,801 | 51,898  |
| Mars           | launch Earth, land Mars, launch Mars, land Earth            | 14,606 | 33,388  |
| Passenger ship | launch Earth, land Moon, launch Moon, land Mars, launch Mars, land Earth | 75,432 | 212,161 |

## Prerequisites

| Requirement | Version | Notes |
| ----------- | ------- | ----- |
| Elixir | 1.18 (minimum 1.17) | `~> 1.17` in `mix.exs` |
| Erlang/OTP | 25 | |

Both versions are pinned in `.tool-versions`, so with `asdf` or `mise` installed
the toolchain comes from there:

```sh
asdf install
```

Nothing else is needed:

- **No database.** Ecto is a dependency, but only for `embedded_schema` and
  changesets as a validation layer — no repo, no migrations, nothing to create.
- **No Node or npm.** Tailwind and esbuild are standalone binaries that
  `mix setup` downloads, and daisyUI arrives as a Mix dependency.

## Setting it up

```sh
mix setup        # fetch deps, install and build assets
mix phx.server   # http://localhost:4000
mix test         # 98 tests + 3 doctests, no database required
mix precommit    # the full gate: compile, deps, format, credo, test
```

### The gate

`mix precommit` is the single command to run before pushing:

| Step | Catches |
| ---- | ------- |
| `compile --warnings-as-errors` | unused variables, missing `@impl`, unreachable clauses |
| `deps.unlock --unused` | dependencies left in `mix.lock` after being dropped |
| `format` | formatting drift |
| `credo --strict` | complexity, nesting depth, alias ordering, missing docs |
| `dialyzer` | `@spec`s that disagree with the code, unreachable clauses |
| `test` | the suite |

`credo --strict` currently reports no issues across all 25 source files. Strict
mode is deliberate — it turns on the nitpick checks (cyclomatic complexity,
function arity, alias usage) that the default run skips, which is the half worth
having on a codebase this size.

Every public function carries a `@spec`, and `dialyzer` is what stops those from
becoming decoration: it currently reports 0 errors. The first run spends about a
minute building its PLT into `priv/plts/` (gitignored); later runs take a
second.

Note that `format` rewrites files in place, so `mix precommit` can leave the
working tree modified even when every step passes. Check `git status` before
committing.

## The solution

```
lib/nasa_fuel/
  flight.ex              context; the only module the web layer talks to
  flight/fuel.ex         pure arithmetic — no Ecto, no web
  flight/mission.ex      embedded_schema: mass + steps, validation only
  flight/step.ex         embedded_schema: one action at one planet
  flight/planet.ex       supported bodies and their gravity
lib/nasa_fuel_web/live/
  mission_live.ex        the whole UI
```

`Fuel` knows nothing about Ecto or Phoenix — a step is any map carrying
`:action` and `:planet`, and it returns `{:ok, _}` / `{:error, _}` tuples. That
keeps the interesting logic testable without a socket or a changeset. `Flight`
owns the shape of the form params so the LiveView never reaches into
`Ecto.Changeset` or the calculator directly.

Adding a planet means adding one line to `flight/planet.ex`. The select options,
the `Ecto.Enum` validation and the calculator all derive from that list.

### The fold runs backwards

This is the part of the problem that is easy to get wrong. A flight path is
folded **last step first**.

Fuel burned late in a mission has to be lifted off the ground by every step
before it, so each step is costed against the dry mass *plus all fuel accrued
after it*. Folding forwards instead — costing step 1 against the bare dry mass,
then step 2, and so on — produces a number that looks plausible and is too low.

Apollo 11, dry mass 28,801 kg:

| # | Manoeuvre     | Mass carried | Fuel   |
| - | ------------- | ------------ | ------ |
| 1 | Launch Earth  | 47,711       | 32,988 |
| 2 | Land Moon     | 45,249       |  2,462 |
| 3 | Launch Moon   | 42,248       |  3,001 |
| 4 | Land Earth    | 28,801       | 13,447 |
|   |               | **Total**    | **51,898** |

Only the last step is costed against the bare 28,801 kg. The UI shows this
"mass carried" column so the reverse fold is visible rather than implied, and
the tests assert the intermediate masses so a regression to a forward fold fails
loudly.

### Validation

`embedded_schema` plus changesets gives validation, error messages and nested
inputs without a database, and `Ecto.Enum` rejects unsupported planets and
actions for free. Non-positive, fractional and non-numeric masses are rejected
by the changeset, an empty flight path by `cast_embed(required: true)`. `Fuel`
then guards its own input independently, so it cannot be misused by a future
caller that skips the changeset.

The path is also validated as a whole, not just field by field. A ship already
in flight cannot launch again, one already on the ground cannot land again, and
it can only depart from wherever it last touched down — so "launch Earth, launch
Moon" and "land Moon, launch Mars" are both rejected.

One rule is deliberately absent: that a path must open with a launch. The brief
costs landing Apollo 11 on Earth as a mission in its own right, so a path that
begins with a landing is legitimate input rather than a mistake.

Continuity is only judged once every step is complete. A half-filled step is
already reporting "can't be blank", and a second complaint about a path it
cannot form yet is noise.

Every event rebuilds the changeset from the raw params and recosts the mission,
so an invalid mission clears the result rather than leaving a stale total on
screen — the number shown always matches the path shown.

Errors are only shown once earned. LiveView's client marks inputs the user has
not touched with a companion `_unused_<field>` param, which `used_input?/1`
reads to keep errors hidden. Params built server-side — clearing the form,
adding a step, loading a preset — have no client to do that for them, so
`MissionLive` marks every blank field on the way in. That marking lives in the
LiveView rather than the context on purpose: it is a detail of LiveView's form
protocol, not of flight planning, and `Flight` stays free of web concerns like
`Fuel` does. This hides error *display* only: a blank mission is still invalid,
so no total is shown and the pending hint explains what is missing.
