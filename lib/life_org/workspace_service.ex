defmodule LifeOrg.WorkspaceService do
  import Ecto.Query, warn: false
  alias LifeOrg.{Repo, Workspace, JournalEntry, Todo, Conversation, Projects, AttachmentService}

  def list_workspaces(user_id) do
    Workspace
    |> where([w], w.user_id == ^user_id)
    |> order_by([w], [desc: w.is_default, asc: w.name])
    |> Repo.all()
  end

  def get_workspace(id, user_id) do
    Workspace
    |> where([w], w.id == ^id and w.user_id == ^user_id)
    |> Repo.one()
  end
  
  def get_workspace(id) do
    Repo.get(Workspace, id)
  end

  def get_workspace!(id, user_id) do
    Workspace
    |> where([w], w.id == ^id and w.user_id == ^user_id)
    |> Repo.one!()
  end
  
  def get_workspace!(id) do
    Repo.get!(Workspace, id)
  end

  def get_workspace_by_name(name, user_id) do
    Repo.get_by(Workspace, name: name, user_id: user_id)
  end

  def get_default_workspace(user_id) do
    case Repo.get_by(Workspace, is_default: true, user_id: user_id) do
      nil -> 
        # If no default workspace exists, get the first one for this user
        Workspace
        |> where([w], w.user_id == ^user_id)
        |> first(:id)
        |> Repo.one()
      workspace -> workspace
    end
  end
  
  def ensure_default_workspace(user) do
    case get_default_workspace(user.id) do
      nil ->
        # Create a default workspace for the user
        create_workspace(%{
          name: "Personal",
          description: "Default personal workspace",
          is_default: true,
          user_id: user.id
        })
      workspace ->
        {:ok, workspace}
    end
  end

  def create_workspace(attrs \\ %{}) do
    %Workspace{}
    |> Workspace.changeset(attrs)
    |> maybe_update_default(attrs["user_id"] || attrs[:user_id])
    |> Repo.insert()
  end

  def update_workspace(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.changeset(attrs)
    |> maybe_update_default(workspace.user_id)
    |> Repo.update()
  end

  def delete_workspace(%Workspace{} = workspace) do
    if workspace.is_default do
      {:error, "Cannot delete the default workspace"}
    else
      Repo.delete(workspace)
    end
  end

  def set_default_workspace(%Workspace{} = workspace) do
    Repo.transaction(fn ->
      # First, unset all other defaults for this user
      from(w in Workspace, where: w.is_default == true and w.user_id == ^workspace.user_id)
      |> Repo.update_all(set: [is_default: false])

      # Then set this one as default
      workspace
      |> Workspace.changeset(%{is_default: true})
      |> Repo.update!()
    end)
  end

  # Journal Entry functions
  def list_journal_entries(workspace_id) do
    JournalEntry
    |> where([j], j.workspace_id == ^workspace_id)
    |> order_by([j], desc: j.entry_date)
    |> Repo.all()
  end

  def get_journal_entry(id, user_id) do
    from(j in JournalEntry,
      join: w in Workspace,
      on: j.workspace_id == w.id,
      where: j.id == ^id and w.user_id == ^user_id,
      select: j
    )
    |> Repo.one()
  end

  def create_journal_entry(attrs, workspace_id) do
    attrs = Map.put(attrs, "workspace_id", workspace_id)
    
    %JournalEntry{}
    |> JournalEntry.changeset(attrs)
    |> Repo.insert()
  end

  def update_journal_entry(%JournalEntry{} = entry, attrs) do
    entry
    |> JournalEntry.changeset(attrs)
    |> Repo.update()
  end

  def delete_journal_entry(%JournalEntry{} = entry) do
    # Delete associated attachments (files and database records)
    AttachmentService.delete_journal_attachments(entry.id)

    # Delete the journal entry (database will cascade delete conversations via foreign key)
    Repo.delete(entry)
  end

  # Todo functions
  def get_todo(id) do
    Todo
    |> Repo.get!(id)
    |> Repo.preload([:workspace, :journal_entry, :projects])
  end

  def get_todo(id, user_id) do
    from(t in Todo,
      join: w in Workspace,
      on: t.workspace_id == w.id,
      where: t.id == ^id and w.user_id == ^user_id,
      preload: [:workspace, :journal_entry, :projects],
      select: t
    )
    |> Repo.one()
  end

  def list_todos(workspace_id) do
    Todo
    |> where([t], t.workspace_id == ^workspace_id)
    |> where([t], t.is_template == false or is_nil(t.is_template))  # Exclude recurring templates
    |> join(:left, [t], c in assoc(t, :comments))
    |> group_by([t], t.id)
    |> select([t, c], %{t | comment_count: count(c.id)})
    |> order_by([t], [desc: t.current, asc: t.position, desc: fragment("FIELD(?, 'high', 'medium', 'low')", t.priority), asc: t.inserted_at])
    |> Repo.all()
    |> Repo.preload([:workspace, :journal_entry, :projects])
  end

  def list_journal_todos(journal_entry_id) do
    Todo
    |> where([t], t.journal_entry_id == ^journal_entry_id)
    |> where([t], t.is_template == false or is_nil(t.is_template))  # Exclude recurring templates
    |> join(:left, [t], c in assoc(t, :comments))
    |> group_by([t], t.id)
    |> select([t, c], %{t | comment_count: count(c.id)})
    |> order_by([t], [desc: fragment("FIELD(?, 'high', 'medium', 'low')", t.priority), asc: t.inserted_at])
    |> Repo.all()
    |> Repo.preload([:journal_entry, :projects])
  end

  def create_todo(attrs, workspace_id) do
    attrs = Map.put(attrs, "workspace_id", workspace_id)
    attrs = maybe_set_position(attrs, workspace_id)
    project_names = Map.get(attrs, "projects", [])
    
    result = %Todo{}
    |> Todo.changeset(Map.drop(attrs, ["projects"]))
    |> Repo.insert()
    
    case result do
      {:ok, todo} ->
        todo = associate_todo_with_projects(todo, project_names, workspace_id)
        {:ok, Repo.preload(todo, [:workspace, :journal_entry, :projects])}
      error ->
        error
    end
  end

  def update_todo(%Todo{} = todo, attrs) do
    project_names = Map.get(attrs, "projects", nil)
    
    case todo
         |> Todo.changeset(Map.drop(attrs, ["projects"]))
         |> Repo.update() do
      {:ok, updated_todo} ->
        updated_todo = if project_names != nil do
          associate_todo_with_projects(updated_todo, project_names, updated_todo.workspace_id)
        else
          updated_todo
        end
        {:ok, Repo.preload(updated_todo, [:workspace, :journal_entry, :projects], force: true)}
      error -> 
        error
    end
  end

  def delete_todo(%Todo{} = todo) do
    # Delete associated attachments (files and database records)
    AttachmentService.delete_todo_attachments(todo.id)

    # Delete the todo (database will cascade delete conversations and chat_messages automatically)
    Repo.delete(todo)
  end

  # Conversation functions
  def list_conversations(workspace_id) do
    Conversation
    |> where([c], c.workspace_id == ^workspace_id)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  def create_conversation(attrs, workspace_id) do
    attrs = Map.put(attrs, "workspace_id", workspace_id)
    
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  # Private helper functions
  defp maybe_update_default(changeset, user_id) do
    case Ecto.Changeset.get_change(changeset, :is_default) do
      true when not is_nil(user_id) ->
        # If setting this workspace as default, unset others for this user
        from(w in Workspace, where: w.is_default == true and w.user_id == ^user_id)
        |> Repo.update_all(set: [is_default: false])
        changeset
      _ ->
        changeset
    end
  end

  defp associate_todo_with_projects(todo, project_names, workspace_id) when is_list(project_names) do
    # Filter out empty strings and nil values
    project_names = project_names
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    
    if Enum.empty?(project_names) do
      # Clear all project associations
      todo
      |> Repo.preload(:projects)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:projects, [])
      |> Repo.update!()
    else
      # Get or create projects
      projects = Projects.get_or_create_projects(workspace_id, project_names)
      
      # Associate projects with todo
      todo
      |> Repo.preload(:projects)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:projects, projects)
      |> Repo.update!()
    end
  end
  
  defp associate_todo_with_projects(todo, project_names, workspace_id) when is_binary(project_names) do
    # Convert comma-separated string to list
    project_list = project_names
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    
    associate_todo_with_projects(todo, project_list, workspace_id)
  end
  
  defp associate_todo_with_projects(todo, _, _), do: todo

  defp maybe_set_position(attrs, workspace_id) do
    case Map.get(attrs, "position") do
      nil ->
        max_position = from(t in Todo, 
          where: t.workspace_id == ^workspace_id, 
          select: max(t.position))
        |> Repo.one()
        
        position = (max_position || 0) + 1000
        Map.put(attrs, "position", position)
      _ ->
        attrs
    end
  end

  def reorder_todos(workspace_id, todo_id_order) do
    Repo.transaction(fn ->
      todo_id_order
      |> Enum.with_index()
      |> Enum.each(fn {todo_id, index} ->
        position = index * 1000
        from(t in Todo, where: t.id == ^todo_id and t.workspace_id == ^workspace_id)
        |> Repo.update_all(set: [position: position])
      end)
    end)
  end

  # Recurring todo helper functions
  def get_recurring_template(todo_id) do
    Repo.get_by(Todo, id: todo_id, is_template: true)
  end

  def get_template_for_occurrence(%Todo{parent_todo_id: parent_id}) when not is_nil(parent_id) do
    Repo.get(Todo, parent_id)
  end

  def get_template_for_occurrence(_), do: nil

  def list_recurring_templates(workspace_id) do
    Todo
    |> where([t], t.workspace_id == ^workspace_id)
    |> where([t], t.is_template == true)
    |> order_by([t], asc: t.title)
    |> Repo.all()
  end
end