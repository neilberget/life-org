defmodule Mix.Tasks.User.Create do
  use Mix.Task
  
  @shortdoc "Creates a new user with the specified email and password"
  
  @moduledoc """
  Creates a new user account.
  
  ## Usage
  
      mix user.create <email> <password>
      
  ## Examples
  
      mix user.create admin@example.com secretpassword123
  """
  
  @impl Mix.Task
  def run([email, password]) do
    Mix.Task.run("app.start")
    
    case LifeOrg.Accounts.register_user(%{
      email: email,
      password: password
    }) do
      {:ok, user} ->
        Mix.shell().info("User created successfully!")
        Mix.shell().info("Email: #{user.email}")
        Mix.shell().info("ID: #{user.id}")
        
        # Mark the user as confirmed since we're creating them manually
        confirmed_user = 
          user
          |> LifeOrg.Accounts.User.confirm_changeset()
          |> LifeOrg.Repo.update!()
        
        # Create default workspace for the user
        {:ok, _workspace} = LifeOrg.WorkspaceService.ensure_default_workspace(confirmed_user)
        
        Mix.shell().info("User has been confirmed and can log in immediately.")
        Mix.shell().info("Default workspace created for the user.")
        
      {:error, changeset} ->
        Mix.shell().error("Failed to create user:")
        
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
        |> Enum.each(fn {field, errors} ->
          Enum.each(errors, fn error ->
            Mix.shell().error("  #{field}: #{error}")
          end)
        end)
    end
  end
  
  def run(_) do
    Mix.shell().error("Usage: mix user.create <email> <password>")
    Mix.shell().error("Example: mix user.create admin@example.com secretpassword123")
  end
end