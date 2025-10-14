defmodule LifeOrgWeb.API.V1.TodoJSON do
  alias LifeOrg.Todo

  def index(%{todos: todos}) do
    %{data: for(todo <- todos, do: data(todo))}
  end

  def show(%{todo: todo}) do
    %{data: data(todo)}
  end

  defp data(%Todo{} = todo) do
    %{
      id: todo.id,
      title: todo.title,
      description: todo.description,
      completed: todo.completed,
      priority: todo.priority,
      due_date: todo.due_date,
      due_time: todo.due_time,
      current: todo.current,
      ai_generated: todo.ai_generated,
      tags: todo.tags || [],
      position: todo.position,
      workspace_id: todo.workspace_id,
      workspace_name: workspace_name(todo),
      journal_entry_id: todo.journal_entry_id,
      projects: projects_data(todo),
      inserted_at: todo.inserted_at,
      updated_at: todo.updated_at
    }
  end

  defp projects_data(%{projects: projects}) when is_list(projects) do
    Enum.map(projects, fn project ->
      %{
        id: project.id,
        name: project.name,
        color: project.color,
        url: project.url,
        favicon_url: project.favicon_url
      }
    end)
  end

  defp projects_data(_), do: []

  defp workspace_name(%{workspace: %{name: name}}), do: name
  defp workspace_name(_), do: nil
end
