defmodule LifeOrg.WorkspaceService do
  import Ecto.Query, warn: false
  alias LifeOrg.{Repo, Workspace, JournalEntry, Todo, Idea, Conversation, Projects, AttachmentService}
  alias LifeOrg.{WorkspaceUser, WorkspaceInvitation, Accounts.User}

  def list_workspaces(user_id) do
    # Get both owned workspaces and shared workspaces
    owned_query = from w in Workspace, where: w.user_id == ^user_id

    shared_query = from w in Workspace,
      join: wu in WorkspaceUser,
      on: wu.workspace_id == w.id,
      where: wu.user_id == ^user_id

    # Union both queries and order by default status and name
    from(w in subquery(union(owned_query, ^shared_query)),
      order_by: [desc: w.is_default, asc: w.name]
    )
    |> Repo.all()
  end

  def get_workspace(id, user_id) do
    # Check if user owns the workspace or is a member
    from(w in Workspace,
      left_join: wu in WorkspaceUser,
      on: wu.workspace_id == w.id and wu.user_id == ^user_id,
      where: w.id == ^id and (w.user_id == ^user_id or not is_nil(wu.id)),
      limit: 1
    )
    |> Repo.one()
  end
  
  def get_workspace(id) do
    Repo.get(Workspace, id)
  end

  def get_workspace!(id, user_id) do
    # Check if user owns the workspace or is a member
    from(w in Workspace,
      left_join: wu in WorkspaceUser,
      on: wu.workspace_id == w.id and wu.user_id == ^user_id,
      where: w.id == ^id and (w.user_id == ^user_id or not is_nil(wu.id)),
      limit: 1
    )
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
    user_id = attrs["user_id"] || attrs[:user_id]

    Repo.transaction(fn ->
      workspace =
        %Workspace{}
        |> Workspace.changeset(attrs)
        |> maybe_update_default(user_id)
        |> Repo.insert!()

      # Create workspace_user entry marking this user as owner
      %WorkspaceUser{}
      |> WorkspaceUser.changeset(%{
        workspace_id: workspace.id,
        user_id: user_id,
        is_owner: true
      })
      |> Repo.insert!()

      workspace
    end)
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

  def is_workspace_owner?(workspace_id, user_id) do
    case Repo.get_by(Workspace, id: workspace_id, user_id: user_id) do
      nil -> false
      _ -> true
    end
  end

  def has_workspace_access?(workspace_id, user_id) do
    # Check if user is owner or member
    query = from(w in Workspace,
      left_join: wu in WorkspaceUser,
      on: wu.workspace_id == w.id and wu.user_id == ^user_id,
      where: w.id == ^workspace_id and (w.user_id == ^user_id or not is_nil(wu.id)),
      select: count(w.id)
    )

    Repo.one(query) > 0
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

  # Workspace Invitation functions
  def create_invitation(workspace_id, email, inviter_user_id) do
    # Check if user with email exists
    case Repo.get_by(User, email: email) do
      nil ->
        {:error, "No user found with that email address"}

      user ->
        # Check if user is already a member
        if has_workspace_access?(workspace_id, user.id) do
          {:error, "User is already a member of this workspace"}
        else
          # Check for existing pending invitation
          existing = Repo.get_by(WorkspaceInvitation,
            workspace_id: workspace_id,
            email: email,
            status: "pending"
          )

          if existing do
            {:error, "An invitation has already been sent to this email"}
          else
            WorkspaceInvitation.create_changeset(%{
              workspace_id: workspace_id,
              email: email,
              invited_by_user_id: inviter_user_id
            })
            |> Repo.insert()
          end
        end
    end
  end

  def list_pending_invitations(user_email) do
    WorkspaceInvitation
    |> where([i], i.email == ^user_email and i.status == "pending")
    |> where([i], i.expires_at > ^DateTime.utc_now() or is_nil(i.expires_at))
    |> preload([:workspace, :invited_by])
    |> Repo.all()
  end

  def list_workspace_invitations(workspace_id) do
    WorkspaceInvitation
    |> where([i], i.workspace_id == ^workspace_id)
    |> order_by([i], desc: i.inserted_at)
    |> preload([:invited_by])
    |> Repo.all()
  end

  def accept_invitation(invitation_id, user_id) do
    invitation = Repo.get(WorkspaceInvitation, invitation_id)
      |> Repo.preload(:workspace)

    cond do
      is_nil(invitation) ->
        {:error, "Invitation not found"}

      invitation.status != "pending" ->
        {:error, "Invitation has already been #{invitation.status}"}

      not is_nil(invitation.expires_at) && DateTime.compare(invitation.expires_at, DateTime.utc_now()) == :lt ->
        {:error, "Invitation has expired"}

      true ->
        user = Repo.get(User, user_id)

        if user.email != invitation.email do
          {:error, "This invitation was sent to a different email address"}
        else
          Repo.transaction(fn ->
            # Create workspace_user entry
            %WorkspaceUser{}
            |> WorkspaceUser.changeset(%{
              workspace_id: invitation.workspace_id,
              user_id: user_id,
              is_owner: false
            })
            |> Repo.insert!()

            # Update invitation status
            invitation
            |> Ecto.Changeset.change(%{status: "accepted"})
            |> Repo.update!()

            invitation.workspace
          end)
        end
    end
  end

  def decline_invitation(invitation_id, user_id) do
    invitation = Repo.get(WorkspaceInvitation, invitation_id)
    user = Repo.get(User, user_id)

    cond do
      is_nil(invitation) ->
        {:error, "Invitation not found"}

      user.email != invitation.email ->
        {:error, "This invitation was sent to a different email address"}

      invitation.status != "pending" ->
        {:error, "Invitation has already been #{invitation.status}"}

      true ->
        invitation
        |> Ecto.Changeset.change(%{status: "declined"})
        |> Repo.update()
    end
  end

  def cancel_invitation(invitation_id, workspace_id, user_id) do
    # Only workspace owner can cancel invitations
    if is_workspace_owner?(workspace_id, user_id) do
      invitation = Repo.get_by(WorkspaceInvitation, id: invitation_id, workspace_id: workspace_id)

      if invitation do
        Repo.delete(invitation)
      else
        {:error, "Invitation not found"}
      end
    else
      {:error, "Only workspace owner can cancel invitations"}
    end
  end

  # Workspace Member functions
  def list_workspace_members(workspace_id) do
    WorkspaceUser
    |> where([wu], wu.workspace_id == ^workspace_id)
    |> preload(:user)
    |> Repo.all()
  end

  def remove_member(workspace_id, member_user_id, requesting_user_id) do
    # Only workspace owner can remove members
    if is_workspace_owner?(workspace_id, requesting_user_id) do
      # Don't allow owner to remove themselves (they should use leave_workspace instead)
      if member_user_id == requesting_user_id do
        {:error, "Use leave_workspace to remove yourself from the workspace"}
      else
        workspace_user = Repo.get_by(WorkspaceUser, workspace_id: workspace_id, user_id: member_user_id)

        if workspace_user do
          Repo.delete(workspace_user)
        else
          {:error, "User is not a member of this workspace"}
        end
      end
    else
      {:error, "Only workspace owner can remove members"}
    end
  end

  def leave_workspace(workspace_id, user_id) do
    # If user is the owner, delete the workspace
    if is_workspace_owner?(workspace_id, user_id) do
      workspace = Repo.get(Workspace, workspace_id)
      delete_workspace(workspace)
    else
      # Otherwise, just remove them from workspace_users
      workspace_user = Repo.get_by(WorkspaceUser, workspace_id: workspace_id, user_id: user_id)

      if workspace_user do
        Repo.delete(workspace_user)
      else
        {:error, "You are not a member of this workspace"}
      end
    end
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

  # Idea functions
  def list_ideas(workspace_id) do
    Idea
    |> where([i], i.workspace_id == ^workspace_id)
    |> order_by([i], [asc: i.position, desc: i.inserted_at])
    |> Repo.all()
    |> Repo.preload([:workspace, :journal_entry])
  end

  def get_idea(id, user_id) do
    from(i in Idea,
      join: w in Workspace,
      on: i.workspace_id == w.id,
      where: i.id == ^id and w.user_id == ^user_id,
      preload: [:workspace, :journal_entry],
      select: i
    )
    |> Repo.one()
  end

  def create_idea(attrs, workspace_id) do
    attrs = Map.put(attrs, "workspace_id", workspace_id)
    attrs = maybe_set_idea_position(attrs, workspace_id)

    %Idea{}
    |> Idea.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, idea} -> {:ok, Repo.preload(idea, [:workspace, :journal_entry])}
      error -> error
    end
  end

  def update_idea(%Idea{} = idea, attrs) do
    idea
    |> Idea.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_idea} -> {:ok, Repo.preload(updated_idea, [:workspace, :journal_entry], force: true)}
      error -> error
    end
  end

  def delete_idea(%Idea{} = idea) do
    Repo.delete(idea)
  end

  def convert_idea_to_todo(%Idea{} = idea) do
    Repo.transaction(fn ->
      # Create new todo with idea's data
      todo_attrs = %{
        "title" => idea.title,
        "description" => idea.description,
        "tags" => idea.tags,
        "workspace_id" => idea.workspace_id,
        "journal_entry_id" => idea.journal_entry_id,
        "ai_generated" => false
      }

      case create_todo(todo_attrs, idea.workspace_id) do
        {:ok, todo} ->
          # Mark idea as converted
          case update_idea(idea, %{"status" => "converted"}) do
            {:ok, _updated_idea} -> todo
            {:error, changeset} -> Repo.rollback(changeset)
          end
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def convert_todo_to_idea(%Todo{} = todo) do
    Repo.transaction(fn ->
      # Create new idea with todo's data
      idea_attrs = %{
        "title" => todo.title,
        "description" => todo.description,
        "tags" => todo.tags,
        "workspace_id" => todo.workspace_id,
        "journal_entry_id" => todo.journal_entry_id,
        "status" => "captured"
      }

      case create_idea(idea_attrs, todo.workspace_id) do
        {:ok, idea} ->
          # Delete the todo
          case delete_todo(todo) do
            {:ok, _deleted_todo} -> idea
            {:error, changeset} -> Repo.rollback(changeset)
          end
        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp maybe_set_idea_position(attrs, workspace_id) do
    if Map.has_key?(attrs, "position") do
      attrs
    else
      max_position = Idea
        |> where([i], i.workspace_id == ^workspace_id)
        |> select([i], max(i.position))
        |> Repo.one()
        |> Kernel.||(0)

      Map.put(attrs, "position", max_position + 1000)
    end
  end
end