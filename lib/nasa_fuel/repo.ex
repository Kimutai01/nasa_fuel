defmodule NasaFuel.Repo do
  use Ecto.Repo,
    otp_app: :nasa_fuel,
    adapter: Ecto.Adapters.Postgres
end
