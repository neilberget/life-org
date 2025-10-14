defmodule LifeOrgWeb.API.V1.TodoController do
  use LifeOrgWeb, :controller

  alias LifeOrg.{WorkspaceService, Repo, Todo}
  import Ecto.Query

  action_fallback LifeOrgWeb.API.V1.FallbackController

  def index(conn, params) do
    user = conn.assigns.current_user
    workspace_id_param = params["workspace_id"]
    workspace_name_param = params["workspace"]

    cond do
      workspace_name_param ->
        # Filter by workspace name(s)
        workspace_names =
          if String.contains?(workspace_name_param, ",") do
            workspace_name_param |> String.split(",") |> Enum.map(&String.trim/1)
          else
            [workspace_name_param]
          end

        user_workspaces = WorkspaceService.list_workspaces(user.id)
        workspace_ids =
          user_workspaces
          |> Enum.filter(fn w -> w.name in workspace_names end)
          |> Enum.map(& &1.id)

        if Enum.empty?(workspace_ids) do
          {:error, :not_found}
        else
          todos =
            Todo
            |> where([t], t.workspace_id in ^workspace_ids)
            |> apply_order_by(params)
            |> apply_query_filters(params)
            |> Repo.all()
            |> Repo.preload([:journal_entry, :projects])
            |> apply_per_workspace_limit(params)

          render(conn, :index, todos: todos)
        end

      workspace_id_param && String.contains?(workspace_id_param, ",") ->
        # Multiple workspace IDs
        workspace_ids =
          workspace_id_param
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&String.to_integer/1)

        # Verify all workspaces belong to user
        user_workspace_ids = WorkspaceService.list_workspaces(user.id) |> Enum.map(& &1.id)
        invalid_ids = workspace_ids -- user_workspace_ids

        if Enum.empty?(invalid_ids) do
          todos =
            Todo
            |> where([t], t.workspace_id in ^workspace_ids)
            |> apply_order_by(params)
            |> apply_query_filters(params)
            |> Repo.all()
            |> Repo.preload([:journal_entry, :projects])
            |> apply_per_workspace_limit(params)

          render(conn, :index, todos: todos)
        else
          {:error, :not_found}
        end

      workspace_id_param ->
        # Single workspace ID
        workspace_id = String.to_integer(workspace_id_param)

        case WorkspaceService.get_workspace(workspace_id, user.id) do
          nil ->
            {:error, :not_found}

          _workspace ->
            todos =
              WorkspaceService.list_todos(workspace_id)
              |> apply_filters(params)
              |> apply_ordering(params)
              |> apply_per_workspace_limit(params)

            render(conn, :index, todos: todos)
        end

      true ->
        # All workspaces
        workspaces = WorkspaceService.list_workspaces(user.id)
        workspace_ids = Enum.map(workspaces, & &1.id)

        todos =
          Todo
          |> where([t], t.workspace_id in ^workspace_ids)
          |> apply_order_by(params)
          |> apply_query_filters(params)
          |> Repo.all()
          |> Repo.preload([:journal_entry, :projects])
          |> apply_per_workspace_limit(params)

        render(conn, :index, todos: todos)
    end
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case WorkspaceService.get_todo(id, user.id) do
      nil ->
        {:error, :not_found}

      todo ->
        render(conn, :show, todo: todo)
    end
  end

  def create(conn, %{"todo" => todo_params}) do
    user = conn.assigns.current_user
    workspace_id = todo_params["workspace_id"]

    case WorkspaceService.get_workspace(workspace_id, user.id) do
      nil ->
        {:error, :not_found}

      _workspace ->
        case WorkspaceService.create_todo(todo_params, workspace_id) do
          {:ok, todo} ->
            conn
            |> put_status(:created)
            |> render(:show, todo: todo)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  def update(conn, %{"id" => id, "todo" => todo_params}) do
    user = conn.assigns.current_user

    case WorkspaceService.get_todo(id, user.id) do
      nil ->
        {:error, :not_found}

      todo ->
        case WorkspaceService.update_todo(todo, todo_params) do
          {:ok, updated_todo} ->
            render(conn, :show, todo: updated_todo)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case WorkspaceService.get_todo(id, user.id) do
      nil ->
        {:error, :not_found}

      todo ->
        case WorkspaceService.delete_todo(todo) do
          {:ok, _todo} ->
            send_resp(conn, :no_content, "")

          {:error, _changeset} ->
            {:error, :unprocessable_entity}
        end
    end
  end

  defp apply_order_by(query, %{"order_by" => order_by}) do
    case order_by do
      "due_date_asc" -> order_by(query, [t], asc_nulls_last: t.due_date)
      "due_date_desc" -> order_by(query, [t], desc_nulls_last: t.due_date)
      "priority_asc" -> order_by(query, [t], asc: fragment("FIELD(?, 'low', 'medium', 'high')", t.priority))
      "priority_desc" -> order_by(query, [t], desc: fragment("FIELD(?, 'high', 'medium', 'low')", t.priority))
      "inserted_at_asc" -> order_by(query, [t], asc: t.inserted_at)
      "inserted_at_desc" -> order_by(query, [t], desc: t.inserted_at)
      "updated_at_asc" -> order_by(query, [t], asc: t.updated_at)
      "updated_at_desc" -> order_by(query, [t], desc: t.updated_at)
      "title_asc" -> order_by(query, [t], asc: t.title)
      "title_desc" -> order_by(query, [t], desc: t.title)
      "position_asc" -> order_by(query, [t], asc: t.position)
      "position_desc" -> order_by(query, [t], desc: t.position)
      _ -> apply_order_by(query, %{})
    end
  end

  defp apply_order_by(query, _params) do
    # Default ordering: current todos first, then by priority, then by insertion time
    order_by(query, [t], [desc: t.current, desc: fragment("FIELD(?, 'high', 'medium', 'low')", t.priority), asc: t.inserted_at])
  end

  defp apply_per_workspace_limit(todos, %{"per_workspace_limit" => limit}) when is_binary(limit) do
    case Integer.parse(limit) do
      {limit_int, _} when limit_int > 0 -> apply_per_workspace_limit(todos, limit_int)
      _ -> todos
    end
  end

  defp apply_per_workspace_limit(todos, %{"per_workspace_limit" => limit}) when is_integer(limit) and limit > 0 do
    apply_per_workspace_limit(todos, limit)
  end

  defp apply_per_workspace_limit(todos, limit) when is_integer(limit) and limit > 0 do
    todos
    |> Enum.group_by(& &1.workspace_id)
    |> Enum.flat_map(fn {_workspace_id, workspace_todos} ->
      Enum.take(workspace_todos, limit)
    end)
  end

  defp apply_per_workspace_limit(todos, _params), do: todos

  defp apply_ordering(todos, %{"order_by" => order_by}) do
    case order_by do
      "due_date_asc" ->
        Enum.sort_by(todos, & &1.due_date, fn
          nil, nil -> false
          nil, _ -> false
          _, nil -> true
          a, b -> Date.compare(a, b) != :gt
        end)

      "due_date_desc" ->
        Enum.sort_by(todos, & &1.due_date, fn
          nil, nil -> false
          nil, _ -> true
          _, nil -> false
          a, b -> Date.compare(a, b) != :lt
        end)

      "priority_asc" ->
        priority_order = %{"low" => 1, "medium" => 2, "high" => 3}
        Enum.sort_by(todos, &(priority_order[&1.priority] || 0))

      "priority_desc" ->
        priority_order = %{"high" => 1, "medium" => 2, "low" => 3}
        Enum.sort_by(todos, &(priority_order[&1.priority] || 999))

      "inserted_at_asc" ->
        Enum.sort_by(todos, & &1.inserted_at, DateTime)

      "inserted_at_desc" ->
        Enum.sort_by(todos, & &1.inserted_at, {:desc, DateTime})

      "updated_at_asc" ->
        Enum.sort_by(todos, & &1.updated_at, DateTime)

      "updated_at_desc" ->
        Enum.sort_by(todos, & &1.updated_at, {:desc, DateTime})

      "title_asc" ->
        Enum.sort_by(todos, & &1.title)

      "title_desc" ->
        Enum.sort_by(todos, & &1.title, :desc)

      "position_asc" ->
        Enum.sort_by(todos, & &1.position)

      "position_desc" ->
        Enum.sort_by(todos, & &1.position, :desc)

      _ ->
        todos
    end
  end

  defp apply_ordering(todos, _params), do: todos

  defp apply_filters(todos, params) do
    todos
    |> filter_by_completed(params)
    |> filter_by_priority(params)
    |> filter_by_tags(params)
    |> filter_by_due_date(params)
    |> filter_by_current(params)
    |> filter_by_search(params)
    |> filter_by_project(params)
  end

  defp apply_query_filters(query, params) do
    query
    |> filter_query_by_completed(params)
    |> filter_query_by_priority(params)
    |> filter_query_by_tags(params)
    |> filter_query_by_due_date(params)
    |> filter_query_by_current(params)
    |> filter_query_by_search(params)
    |> filter_query_by_project(params)
  end

  defp filter_by_completed(todos, %{"completed" => "true"}), do: Enum.filter(todos, & &1.completed)
  defp filter_by_completed(todos, %{"completed" => "false"}), do: Enum.filter(todos, &(not &1.completed))
  defp filter_by_completed(todos, _), do: todos

  defp filter_query_by_completed(query, %{"completed" => "true"}), do: where(query, [t], t.completed == true)
  defp filter_query_by_completed(query, %{"completed" => "false"}), do: where(query, [t], t.completed == false)
  defp filter_query_by_completed(query, _), do: query

  defp filter_by_priority(todos, %{"priority" => priority}) when is_binary(priority) do
    if String.contains?(priority, ",") do
      priority_list = String.split(priority, ",") |> Enum.map(&String.trim/1)
      filter_by_priority(todos, %{"priority" => priority_list})
    else
      Enum.filter(todos, &(&1.priority == priority))
    end
  end

  defp filter_by_priority(todos, %{"priority" => priorities}) when is_list(priorities) do
    Enum.filter(todos, fn todo ->
      todo.priority in priorities
    end)
  end

  defp filter_by_priority(todos, _), do: todos

  defp filter_query_by_priority(query, %{"priority" => priority}) when is_binary(priority) do
    if String.contains?(priority, ",") do
      priority_list = String.split(priority, ",") |> Enum.map(&String.trim/1)
      filter_query_by_priority(query, %{"priority" => priority_list})
    else
      where(query, [t], t.priority == ^priority)
    end
  end

  defp filter_query_by_priority(query, %{"priority" => priorities}) when is_list(priorities) do
    where(query, [t], t.priority in ^priorities)
  end

  defp filter_query_by_priority(query, _), do: query

  defp filter_by_tags(todos, %{"tags" => tags}) when is_binary(tags) do
    tag_list = String.split(tags, ",") |> Enum.map(&String.trim/1)
    filter_by_tags(todos, %{"tags" => tag_list})
  end

  defp filter_by_tags(todos, %{"tags" => tags}) when is_list(tags) do
    Enum.filter(todos, fn todo ->
      todo.tags && Enum.any?(tags, &(&1 in todo.tags))
    end)
  end

  defp filter_by_tags(todos, _), do: todos

  defp filter_query_by_tags(query, %{"tags" => tags}) when is_binary(tags) do
    tag_list = String.split(tags, ",") |> Enum.map(&String.trim/1)
    filter_query_by_tags(query, %{"tags" => tag_list})
  end

  defp filter_query_by_tags(query, %{"tags" => tags}) when is_list(tags) do
    Enum.reduce(tags, query, fn tag, acc ->
      where(acc, [t], fragment("JSON_CONTAINS(?, ?)", t.tags, ^Jason.encode!([tag])))
    end)
  end

  defp filter_query_by_tags(query, _), do: query

  defp filter_by_due_date(todos, %{"overdue" => "true"}) do
    today = Date.utc_today()
    Enum.filter(todos, fn todo ->
      todo.due_date && Date.compare(todo.due_date, today) == :lt && !todo.completed
    end)
  end

  defp filter_by_due_date(todos, %{"due_date" => date}) do
    {:ok, due_date} = Date.from_iso8601(date)
    Enum.filter(todos, &(&1.due_date == due_date))
  end

  defp filter_by_due_date(todos, _), do: todos

  defp filter_query_by_due_date(query, %{"overdue" => "true"}) do
    today = Date.utc_today()
    where(query, [t], t.due_date < ^today and t.completed == false)
  end

  defp filter_query_by_due_date(query, %{"due_date" => date}) do
    {:ok, due_date} = Date.from_iso8601(date)
    where(query, [t], t.due_date == ^due_date)
  end

  defp filter_query_by_due_date(query, _), do: query

  defp filter_by_current(todos, %{"current" => "true"}), do: Enum.filter(todos, & &1.current)
  defp filter_by_current(todos, %{"current" => "false"}), do: Enum.filter(todos, &(not &1.current))
  defp filter_by_current(todos, _), do: todos

  defp filter_query_by_current(query, %{"current" => "true"}), do: where(query, [t], t.current == true)
  defp filter_query_by_current(query, %{"current" => "false"}), do: where(query, [t], t.current == false)
  defp filter_query_by_current(query, _), do: query

  defp filter_by_search(todos, %{"q" => search_term}) do
    search_term = String.downcase(search_term)

    Enum.filter(todos, fn todo ->
      String.contains?(String.downcase(todo.title || ""), search_term) ||
        String.contains?(String.downcase(todo.description || ""), search_term)
    end)
  end

  defp filter_by_search(todos, _), do: todos

  defp filter_query_by_search(query, %{"q" => search_term}) do
    search_pattern = "%#{search_term}%"
    where(query, [t], ilike(t.title, ^search_pattern) or ilike(t.description, ^search_pattern))
  end

  defp filter_query_by_search(query, _), do: query

  defp filter_by_project(todos, %{"project" => project}) when is_binary(project) do
    if String.contains?(project, ",") do
      project_list = String.split(project, ",") |> Enum.map(&String.trim/1)
      filter_by_project(todos, %{"project" => project_list})
    else
      Enum.filter(todos, fn todo ->
        todo.projects && Enum.any?(todo.projects, &(&1.name == project))
      end)
    end
  end

  defp filter_by_project(todos, %{"project" => projects}) when is_list(projects) do
    Enum.filter(todos, fn todo ->
      todo.projects && Enum.any?(todo.projects, fn p -> p.name in projects end)
    end)
  end

  defp filter_by_project(todos, _), do: todos

  defp filter_query_by_project(query, %{"project" => project}) when is_binary(project) do
    if String.contains?(project, ",") do
      project_list = String.split(project, ",") |> Enum.map(&String.trim/1)
      filter_query_by_project(query, %{"project" => project_list})
    else
      query
      |> join(:inner, [t], p in assoc(t, :projects))
      |> where([t, p], p.name == ^project)
      |> distinct(true)
    end
  end

  defp filter_query_by_project(query, %{"project" => projects}) when is_list(projects) do
    query
    |> join(:inner, [t], p in assoc(t, :projects))
    |> where([t, p], p.name in ^projects)
    |> distinct(true)
  end

  defp filter_query_by_project(query, _), do: query
end
