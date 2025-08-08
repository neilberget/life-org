defmodule LifeOrg.MCP.Tools.TodoTools do
  @moduledoc """
  MCP tool components for todo operations.
  """

  use Hermes.Server.Component, type: :tool

  alias LifeOrg.{Todo, Repo}
  alias Hermes.Server.Response

  import Ecto.Query

  schema do
    field :query, :string, description: "Search query for todos"
    field :workspace_id, :integer, description: "Optional workspace ID to search in (defaults to default workspace)"
    field :completed, :boolean, description: "Filter by completion status"
    field :tag, :string, description: "Filter by specific tag"
  end

  @impl true
  def execute(params, frame) do
    # Extract query parameter for searching todos
    query = Map.get(params, "query", "")
    search_todos(params, query, frame)
  end

  # Tool implementations for todos

  def search_todos(params, search_query, frame) do
    # Use default workspace if no workspace_id specified
    workspace_id = case Map.get(params, "workspace_id") do
      nil -> 
        # For MCP tools, we don't have user context
        # Use the first workspace as a fallback
        import Ecto.Query
        case LifeOrg.Repo.one(from w in LifeOrg.Workspace, order_by: [asc: w.id], limit: 1) do
          %{id: id} -> id
          _ -> 1
        end
      id -> id
    end
    
    query = from(t in Todo,
      where: t.workspace_id == ^workspace_id,
      order_by: [desc: t.priority, asc: t.due_date, desc: t.inserted_at]
    )

    # Add search filter if query provided
    query = if search_query != "" do
      from(t in query, 
        where: ilike(t.title, ^"%#{search_query}%") or 
               ilike(t.description, ^"%#{search_query}%") or
               fragment("JSON_SEARCH(?, 'one', ?) IS NOT NULL", t.tags, ^"%#{search_query}%"))
    else
      query
    end

    query = case Map.get(params, "completed") do
      nil -> query
      completed -> from(t in query, where: t.completed == ^completed)
    end

    query = case Map.get(params, "tag") do
      nil -> query
      tag -> from(t in query, where: fragment("JSON_CONTAINS(?, ?)", t.tags, ^Jason.encode!([tag])))
    end

    todos = Repo.all(query) |> Enum.map(&format_todo/1)
    
    result = if todos == [] do
      "No todos found#{if search_query != "", do: " matching '#{search_query}'"}"
    else
      todos
      |> Enum.take(10)  # Limit to 10 todos to prevent overly long responses
      |> Enum.map(fn todo ->
        status = if todo.completed, do: "✓", else: "○"
        priority_icon = case todo.priority do
          "high" -> "🔴"
          "medium" -> "🟡" 
          "low" -> "🟢"
          _ -> ""
        end
        # Truncate descriptions to prevent overly long responses
        description = if todo.description && String.length(todo.description) > 100 do
          String.slice(todo.description, 0, 100) <> "..."
        else
          todo.description
        end
        "#{status} #{priority_icon} #{todo.title}#{if description, do: " - #{description}"}"
      end)
      |> Enum.join("\n")
    end
    
    # Ensure the result isn't too long
    final_result = if String.length(result) > 2000 do
      String.slice(result, 0, 2000) <> "\n... (truncated)"
    else
      result
    end
    
    {:reply, Response.json(Response.tool(), final_result), frame}
  end


  # Helper functions
  defp format_todo(todo) do
    %{
      id: todo.id,
      title: todo.title,
      description: todo.description,
      priority: todo.priority,
      tags: todo.tags || [],
      due_date: todo.due_date && to_string(todo.due_date),
      due_time: todo.due_time && Time.to_string(todo.due_time),
      completed: todo.completed,
      ai_generated: todo.ai_generated,
      inserted_at: DateTime.to_iso8601(todo.inserted_at),
      updated_at: DateTime.to_iso8601(todo.updated_at)
    }
  end
end