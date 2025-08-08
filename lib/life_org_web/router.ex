defmodule LifeOrgWeb.Router do
  use LifeOrgWeb, :router

  import LifeOrgWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LifeOrgWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LifeOrgWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/", OrganizerLive
    live "/todo/:id", OrganizerLive
    live "/journal/:id", JournalEntryLive
    
    # Integration settings
    get "/settings/integrations", AuthController, :settings
    delete "/auth/:provider", AuthController, :disconnect
    
    # Admin pages
    live "/admin/api_usage", AdminApiUsageLive
  end

  # OAuth2 authentication routes
  scope "/auth", LifeOrgWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback
  end

  # MCP server endpoint
  forward "/mcp", Hermes.Server.Transport.StreamableHTTP.Plug,
    server: LifeOrg.MCPServer

  # Other scopes may use custom stacks.
  # scope "/api", LifeOrgWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:life_org, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LifeOrgWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", LifeOrgWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/reset_password", UserResetPasswordController, :new
    post "/users/reset_password", UserResetPasswordController, :create
    get "/users/reset_password/:token", UserResetPasswordController, :edit
    put "/users/reset_password/:token", UserResetPasswordController, :update
  end

  scope "/", LifeOrgWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm_email/:token", UserSettingsController, :confirm_email
  end

  scope "/", LifeOrgWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete
    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :edit
    post "/users/confirm/:token", UserConfirmationController, :update
  end
end
