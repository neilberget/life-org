defmodule Mix.Tasks.Deploy do
  @moduledoc """
  Deploy the project to the production server.

  Usage: mix deploy
  """
  use Mix.Task

  @shortdoc "Deploy the project to production server"

  def run(_args) do
    Mix.shell().info("Starting deployment to kestrel...")

    # Get the project root directory
    project_root = File.cwd!()

    # SCP the entire project to kestrel
    Mix.shell().info("Copying files to neil@kestrel:~/docker/projects/life-org...")

    {output, exit_code} = System.cmd(
      "rsync",
      [
        "-avz",
        "--delete",
        "--exclude", ".git",
        "--exclude", "_build",
        "--exclude", "deps",
        "--exclude", "node_modules",
        "--exclude", ".elixir_ls",
        "--exclude", ".env",
        "#{project_root}/",
        "neil@kestrel:~/docker/projects/life-org/"
      ],
      stderr_to_stdout: true
    )

    IO.puts(output)

    if exit_code != 0 do
      Mix.shell().error("✗ File sync failed with exit code #{exit_code}")
      System.halt(1)
    end

    Mix.shell().info("✓ Files synced successfully")

    # Build docker image
    Mix.shell().info("Building docker image...")
    {output, exit_code} = System.cmd(
      "ssh",
      ["neil@kestrel", "cd ~/docker/projects/life-org && docker compose build"],
      stderr_to_stdout: true
    )
    IO.puts(output)

    if exit_code != 0 do
      Mix.shell().error("✗ Docker build failed with exit code #{exit_code}")
      System.halt(1)
    end

    Mix.shell().info("✓ Docker image built successfully")

    # Stop containers
    Mix.shell().info("Stopping containers...")
    {output, exit_code} = System.cmd(
      "ssh",
      ["neil@kestrel", "cd ~/docker/projects/life-org && docker compose down"],
      stderr_to_stdout: true
    )
    IO.puts(output)

    if exit_code != 0 do
      Mix.shell().error("✗ Docker down failed with exit code #{exit_code}")
      System.halt(1)
    end

    Mix.shell().info("✓ Containers stopped")

    # Start containers
    Mix.shell().info("Starting containers...")
    {output, exit_code} = System.cmd(
      "ssh",
      ["neil@kestrel", "cd ~/docker/projects/life-org && docker compose up -d"],
      stderr_to_stdout: true
    )
    IO.puts(output)

    if exit_code != 0 do
      Mix.shell().error("✗ Docker up failed with exit code #{exit_code}")
      System.halt(1)
    end

    Mix.shell().info("✓ Containers started")

    # Run migrations
    Mix.shell().info("Running migrations...")
    {output, exit_code} = System.cmd(
      "ssh",
      ["neil@kestrel", "cd ~/docker/projects/life-org && docker compose exec -T lifeorg /app/bin/life_org eval 'LifeOrg.Release.migrate'"],
      stderr_to_stdout: true
    )
    IO.puts(output)

    if exit_code != 0 do
      Mix.shell().error("✗ Migrations failed with exit code #{exit_code}")
      System.halt(1)
    end

    Mix.shell().info("✓ Migrations completed")
    Mix.shell().info("🚀 Deployment completed successfully!")
  end
end
