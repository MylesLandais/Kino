defmodule KinoWeb.Router do
  use KinoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KinoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug KinoWeb.UserAuth, :fetch_current_user
  end

  pipeline :authenticated do
    plug KinoWeb.UserAuth, :require_authenticated
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :media do
    plug :accepts, ["html"]
  end

  scope "/", KinoWeb do
    pipe_through :browser
    get "/login", AuthController, :login_page
    post "/login", AuthController, :login
    get "/setup", AuthController, :setup_page
    post "/setup", AuthController, :setup
    get "/signup", AuthController, :signup_page
    post "/signup", AuthController, :signup
    delete "/logout", AuthController, :logout
  end

  scope "/", KinoWeb do
    pipe_through [:browser, :authenticated]
    live "/", TheaterLive
    live "/admin/users", AdminUsersLive
    live "/admin/avatar", AdminAvatarLive
    get "/avatar/assets/:id/content", AvatarAssetController, :show
  end

  scope "/", KinoWeb do
    pipe_through :media

    get "/media/:cache_key", MediaController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", KinoWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:kino, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KinoWeb.Telemetry
    end
  end
end
