defmodule NasaFuelWeb.Router do
  use NasaFuelWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NasaFuelWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", NasaFuelWeb do
    pipe_through :browser

    live "/", MissionLive
  end
end
