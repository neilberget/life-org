defmodule LifeOrg.MCPServer do
  @moduledoc """
  MCP (Model Context Protocol) server for Life Organizer.
  Provides AI tools to interact with journal entries and todos.
  """

  use Hermes.Server,
    name: "life-organizer",
    version: "1.0.0",
    capabilities: [:tools]

  # Register all tool components
  component LifeOrg.MCP.Tools.JournalTools
  component LifeOrg.MCP.Tools.TodoTools
end