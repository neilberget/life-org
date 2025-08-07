defmodule LifeOrg.WorkspaceService do
  import Ecto.Query, warn: false
  alias LifeOrg.{Repo, Workspace, JournalEntry, Todo, Conversation}

  def list_workspaces do
    Workspace
    |> order_by([w], [desc: w.is_default, asc: w.name])
    |> Repo.all()
  end

  def get_workspace(id) do
    Repo.get(Workspace, id)
  end

  def get_workspace!(id) do
    Repo.get!(Workspace, id)
  end

  def get_workspace_by_name(name) do
    Repo.get_by(Workspace, name: name)
  end

  def get_default_workspace do
    case Repo.get_by(Workspace, is_default: true) do
      nil -> 
        # If no default workspace exists, get the first one
        Workspace
        |> first(:id)
        |> Repo.one()
      workspace -> workspace
    end
  end

  def create_workspace(attrs \\ %{}) do
    %Workspace{}
    |> Workspace.changeset(attrs)
    |> maybe_update_default()
    |> Repo.insert()
  end

  def update_workspace(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.changeset(attrs)
    |> maybe_update_default()
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
      # First, unset all other defaults
      from(w in Workspace, where: w.is_default == true)
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
    Repo.delete(entry)
  end

  # Todo functions
  def get_todo(id) do
    Todo
    |> Repo.get!(id)
    |> Repo.preload(:journal_entry)
  end

  def list_todos(workspace_id) do
    Todo
    |> where([t], t.workspace_id == ^workspace_id)
    |> join(:left, [t], c in assoc(t, :comments))
    |> group_by([t], t.id)
    |> select([t, c], %{t | comment_count: count(c.id)})
    |> order_by([t], [desc: fragment("FIELD(?, 'high', 'medium', 'low')", t.priority), asc: t.inserted_at])
    |> Repo.all()
    |> Repo.preload(:journal_entry)
  end

  def create_todo(attrs, workspace_id) do
    attrs = Map.put(attrs, "workspace_id", workspace_id)
    
    %Todo{}
    |> Todo.changeset(attrs)
    |> Repo.insert()
  end

  def update_todo(%Todo{} = todo, attrs) do
    case todo
         |> Todo.changeset(attrs)
         |> Repo.update() do
      {:ok, updated_todo} -> {:ok, Repo.preload(updated_todo, :journal_entry)}
      error -> error
    end
  end

  def delete_todo(%Todo{} = todo) do
    # Database will cascade delete conversations and chat_messages automatically
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
  defp maybe_update_default(changeset) do
    case Ecto.Changeset.get_change(changeset, :is_default) do
      true ->
        # If setting this workspace as default, we need to unset others first
        # This will be handled in a transaction during the actual insert/update
        changeset
      _ ->
        changeset
    end
  end
end