defmodule LifeOrgWeb.API.V1.JournalEntryController do
  use LifeOrgWeb, :controller

  alias LifeOrg.{WorkspaceService, Repo}
  alias LifeOrg.JournalEntry

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
          entries =
            JournalEntry
            |> where([j], j.workspace_id in ^workspace_ids)
            |> order_by([j], desc: j.entry_date)
            |> apply_query_filters(params)
            |> Repo.all()

          render(conn, :index, journal_entries: entries)
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
          entries =
            JournalEntry
            |> where([j], j.workspace_id in ^workspace_ids)
            |> order_by([j], desc: j.entry_date)
            |> apply_query_filters(params)
            |> Repo.all()

          render(conn, :index, journal_entries: entries)
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
            entries = apply_filters(WorkspaceService.list_journal_entries(workspace_id), params)
            render(conn, :index, journal_entries: entries)
        end

      true ->
        # All workspaces
        workspaces = WorkspaceService.list_workspaces(user.id)
        workspace_ids = Enum.map(workspaces, & &1.id)

        entries =
          JournalEntry
          |> where([j], j.workspace_id in ^workspace_ids)
          |> order_by([j], desc: j.entry_date)
          |> apply_query_filters(params)
          |> Repo.all()

        render(conn, :index, journal_entries: entries)
    end
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case WorkspaceService.get_journal_entry(id, user.id) do
      nil ->
        {:error, :not_found}

      entry ->
        render(conn, :show, journal_entry: entry)
    end
  end

  def create(conn, %{"journal_entry" => journal_params}) do
    user = conn.assigns.current_user
    workspace_id = journal_params["workspace_id"]

    case WorkspaceService.get_workspace(workspace_id, user.id) do
      nil ->
        {:error, :not_found}

      _workspace ->
        case WorkspaceService.create_journal_entry(journal_params, workspace_id) do
          {:ok, entry} ->
            conn
            |> put_status(:created)
            |> render(:show, journal_entry: entry)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  def update(conn, %{"id" => id, "journal_entry" => journal_params}) do
    user = conn.assigns.current_user

    case WorkspaceService.get_journal_entry(id, user.id) do
      nil ->
        {:error, :not_found}

      entry ->
        case WorkspaceService.update_journal_entry(entry, journal_params) do
          {:ok, updated_entry} ->
            render(conn, :show, journal_entry: updated_entry)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case WorkspaceService.get_journal_entry(id, user.id) do
      nil ->
        {:error, :not_found}

      entry ->
        case WorkspaceService.delete_journal_entry(entry) do
          {:ok, _entry} ->
            send_resp(conn, :no_content, "")

          {:error, _changeset} ->
            {:error, :unprocessable_entity}
        end
    end
  end

  defp apply_filters(entries, params) do
    entries
    |> filter_by_date_range(params)
    |> filter_by_tags(params)
    |> filter_by_search(params)
  end

  defp apply_query_filters(query, params) do
    query
    |> filter_query_by_date_range(params)
    |> filter_query_by_tags(params)
    |> filter_query_by_search(params)
  end

  defp filter_by_date_range(entries, %{"start_date" => start_date, "end_date" => end_date}) do
    {:ok, start_date} = Date.from_iso8601(start_date)
    {:ok, end_date} = Date.from_iso8601(end_date)

    Enum.filter(entries, fn entry ->
      Date.compare(entry.entry_date, start_date) in [:gt, :eq] and
        Date.compare(entry.entry_date, end_date) in [:lt, :eq]
    end)
  end

  defp filter_by_date_range(entries, _), do: entries

  defp filter_query_by_date_range(query, %{"start_date" => start_date, "end_date" => end_date}) do
    {:ok, start_date} = Date.from_iso8601(start_date)
    {:ok, end_date} = Date.from_iso8601(end_date)

    where(query, [j], j.entry_date >= ^start_date and j.entry_date <= ^end_date)
  end

  defp filter_query_by_date_range(query, _), do: query

  defp filter_by_tags(entries, %{"tags" => tags}) when is_binary(tags) do
    tag_list = String.split(tags, ",") |> Enum.map(&String.trim/1)
    filter_by_tags(entries, %{"tags" => tag_list})
  end

  defp filter_by_tags(entries, %{"tags" => tags}) when is_list(tags) do
    Enum.filter(entries, fn entry ->
      entry.tags && Enum.any?(tags, &(&1 in entry.tags))
    end)
  end

  defp filter_by_tags(entries, _), do: entries

  defp filter_query_by_tags(query, %{"tags" => tags}) when is_binary(tags) do
    tag_list = String.split(tags, ",") |> Enum.map(&String.trim/1)
    filter_query_by_tags(query, %{"tags" => tag_list})
  end

  defp filter_query_by_tags(query, %{"tags" => tags}) when is_list(tags) do
    Enum.reduce(tags, query, fn tag, acc ->
      where(acc, [j], fragment("JSON_CONTAINS(?, ?)", j.tags, ^Jason.encode!([tag])))
    end)
  end

  defp filter_query_by_tags(query, _), do: query

  defp filter_by_search(entries, %{"q" => search_term}) do
    search_term = String.downcase(search_term)

    Enum.filter(entries, fn entry ->
      String.contains?(String.downcase(entry.content || ""), search_term)
    end)
  end

  defp filter_by_search(entries, _), do: entries

  defp filter_query_by_search(query, %{"q" => search_term}) do
    search_pattern = "%#{search_term}%"
    where(query, [j], ilike(j.content, ^search_pattern))
  end

  defp filter_query_by_search(query, _), do: query
end
