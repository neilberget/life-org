defmodule Mix.Tasks.User.List do
  use Mix.Task
  
  @shortdoc "Lists all existing users"
  
  @moduledoc """
  Lists all user accounts in the system.
  
  ## Usage
  
      mix user.list
  """
  
  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    
    users = LifeOrg.Repo.all(LifeOrg.Accounts.User)
    
    if Enum.empty?(users) do
      Mix.shell().info("No users found.")
    else
      Mix.shell().info("Users in the system:")
      Mix.shell().info("")
      
      Enum.each(users, fn user ->
        confirmed = if user.confirmed_at, do: "✓", else: "✗"
        Mix.shell().info("  [#{confirmed}] #{user.email} (ID: #{user.id})")
      end)
      
      Mix.shell().info("")
      Mix.shell().info("Legend: [✓] = confirmed, [✗] = unconfirmed")
    end
  end
end