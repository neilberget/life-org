defmodule LifeOrg.MCP.Tools.JournalTools do
  @moduledoc """
  MCP tool components for journal entry operations.
  """

  use Hermes.Server.Component, type: :tool

  alias LifeOrg.{JournalEntry, Repo, WorkspaceService}
  alias Hermes.Server.Response

  import Ecto.Query

  schema do
    field :query, :string, description: "Search query for journal entries"
    field :workspace_id, :integer, description: "Optional workspace ID to search in (defaults to default workspace)"
    field :limit, :integer, default: 20, description: "Maximum number of entries to return"
  end

  @impl true
  def execute(params, frame) do
    # Extract query parameter for searching journal entries
    query_text = Map.get(params, "query", "")
    search_journal_entries(params, query_text, frame)
  end

  # Tool implementations for journal entries

  def search_journal_entries(params, query_text, frame) do
    # Use default workspace if no workspace_id specified
    workspace_id = case Map.get(params, "workspace_id") do
      nil -> 
        default_workspace = WorkspaceService.get_default_workspace()
        default_workspace && default_workspace.id || 1
      id -> id
    end
    limit = min(Map.get(params, "limit", 20), 50)

    query = from(je in JournalEntry,
      where: je.workspace_id == ^workspace_id,
      order_by: [desc: je.entry_date, desc: je.inserted_at],
      limit: ^limit
    )

    query = if query_text != "" do
      from(je in query, where: ilike(je.content, ^"%#{query_text}%"))
    else
      query
    end

    entries = Repo.all(query) |> Enum.map(&format_journal_entry/1)
    
    result = if entries == [] do
      "No journal entries found#{if query_text != "", do: " matching '#{query_text}'"}"
    else
      entries
      |> Enum.map(fn entry ->
        content_preview = if String.length(entry.content) > 100 do
          String.slice(entry.content, 0, 100) <> "..."
        else
          entry.content
        end
        
        "📅 #{entry.entry_date} - #{content_preview}"
      end)
      |> Enum.join("\n")
    end
    
    {:reply, Response.json(Response.tool(), result), frame}
  end

  # Helper functions
  defp format_journal_entry(entry) do
    %{
      id: entry.id,
      content: entry.content,
      tags: entry.tags || [],
      entry_date: to_string(entry.entry_date),
      inserted_at: DateTime.to_iso8601(entry.inserted_at),
      updated_at: DateTime.to_iso8601(entry.updated_at)
    }
  end
end