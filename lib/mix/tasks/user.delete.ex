defmodule Mix.Tasks.User.Delete do
  use Mix.Task
  
  @shortdoc "Deletes a user by email"
  
  @moduledoc """
  Deletes a user account by email address.
  
  ## Usage
  
      mix user.delete <email>
      
  ## Examples
  
      mix user.delete admin@example.com
  """
  
  @impl Mix.Task
  def run([email]) do
    Mix.Task.run("app.start")
    
    case LifeOrg.Repo.get_by(LifeOrg.Accounts.User, email: email) do
      nil ->
        Mix.shell().error("User with email '#{email}' not found.")
        
      user ->
        case LifeOrg.Repo.delete(user) do
          {:ok, _} ->
            Mix.shell().info("User '#{email}' deleted successfully.")
            
          {:error, _changeset} ->
            Mix.shell().error("Failed to delete user '#{email}'.")
        end
    end
  end
  
  def run(_) do
    Mix.shell().error("Usage: mix user.delete <email>")
    Mix.shell().error("Example: mix user.delete admin@example.com")
  end
end