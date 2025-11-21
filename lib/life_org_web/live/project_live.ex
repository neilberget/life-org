defmodule LifeOrgWeb.ProjectLive do
  use LifeOrgWeb, :live_view
  import Ecto.Query

  on_mount {LifeOrgWeb.UserAuth, :ensure_authenticated}

  alias LifeOrg.{
    Repo,
    Projects,
    Projects.Project,
    Todo,
    AIHandler,
    ConversationService,
    WorkspaceService
  }

  alias LifeOrgWeb.Components.{TodoComponent, ChatComponent}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    current_user = socket.assigns.current_user
    current_workspace = WorkspaceService.get_default_workspace(current_user.id)

    # Get the project - support both numeric IDs and slugs
    project = case Integer.parse(id) do
      {project_id, ""} ->
        Projects.get_project!(project_id) |> Repo.preload(:todos)
      _ ->
        # TODO: Add slug support if needed
        nil
    end

    if project && project.workspace_id == current_workspace.id do
      # Load todos for this project
      todos = get_project_todos(project.id)

      # Load conversations for this project
      conversations = ConversationService.list_project_conversations(project.id)

      {:ok,
       socket
       |> assign(:current_user, current_user)
       |> assign(:current_workspace, current_workspace)
       |> assign(:project, project)
       |> assign(:todos, todos)
       |> assign(:conversations, conversations)
       |> assign(:current_conversation, nil)
       |> assign(:chat_messages, [])
       |> assign(:processing_message, false)
       |> assign(:user_timezone, current_user.timezone || "America/Chicago")}
    else
      {:ok,
       socket
       |> put_flash(:error, "Project not found")
       |> push_navigate(to: "/")}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if String.trim(message) == "" do
      {:noreply, socket}
    else
      # Get or create conversation
      conversation =
        case socket.assigns.current_conversation do
          nil ->
            {:ok, conv} =
              ConversationService.get_or_create_project_conversation(
                socket.assigns.project.id,
                socket.assigns.current_workspace.id,
                message
              )

            conv

          conv ->
            conv
        end

      # Add user message
      {:ok, _} = ConversationService.add_message_to_conversation(conversation.id, "user", message)

      # Reload messages
      messages = ConversationService.get_conversation_messages_for_ai(conversation.id)
      conversations = ConversationService.list_project_conversations(socket.assigns.project.id)

      # Process AI response in background
      parent_pid = self()
      project = socket.assigns.project
      project_id = socket.assigns.project.id
      workspace_id = socket.assigns.current_workspace.id
      project_todos = socket.assigns.todos
      all_todos = WorkspaceService.list_todos(workspace_id)

      Task.start(fn ->
        case AIHandler.process_project_message(message, project, project_todos, all_todos, messages, workspace_id) do
          {:ok, assistant_message, _actions} ->
            # Save assistant response to conversation
            ConversationService.add_message_to_conversation(conversation.id, "assistant", assistant_message)
            send(parent_pid, {:ai_response, conversation.id, assistant_message})

          {:error, reason} ->
            send(parent_pid, {:ai_error, reason})
        end
      end)

      {:noreply,
       socket
       |> assign(:current_conversation, conversation)
       |> assign(:chat_messages, messages)
       |> assign(:conversations, conversations)
       |> assign(:processing_message, true)
       |> push_event("clear_chat_input", %{})}
    end
  end

  @impl true
  def handle_event("select_conversation", %{"conversation_id" => conversation_id}, socket) do
    conversation_id = String.to_integer(conversation_id)
    conversation = ConversationService.get_conversation_with_messages(conversation_id)
    messages = ConversationService.get_conversation_messages_for_ai(conversation_id)

    {:noreply,
     socket
     |> assign(:current_conversation, conversation)
     |> assign(:chat_messages, messages)}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    {:noreply,
     socket
     |> assign(:current_conversation, nil)
     |> assign(:chat_messages, [])}
  end

  @impl true
  def handle_event("toggle_todo", %{"id" => id}, socket) do
    todo = WorkspaceService.get_todo(String.to_integer(id))

    case WorkspaceService.update_todo(todo, %{completed: !todo.completed}) do
      {:ok, _updated_todo} ->
        todos = get_project_todos(socket.assigns.project.id)

        {:noreply,
         socket
         |> assign(:todos, todos)
         |> put_flash(:info, "Todo updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Error updating todo")}
    end
  end

  @impl true
  def handle_info({:ai_response, conversation_id, _assistant_message}, socket) do
    # Reload messages
    messages = ConversationService.get_conversation_messages_for_ai(conversation_id)
    conversations = ConversationService.list_project_conversations(socket.assigns.project.id)

    # Reload todos in case AI created/updated any
    todos = get_project_todos(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:chat_messages, messages)
     |> assign(:conversations, conversations)
     |> assign(:todos, todos)
     |> assign(:processing_message, false)}
  end

  @impl true
  def handle_info({:ai_error, reason}, socket) do
    {:noreply,
     socket
     |> assign(:processing_message, false)
     |> put_flash(:error, "AI error: #{inspect(reason)}")}
  end

  defp get_project_todos(project_id) do
    query =
      from t in Todo,
        join: tp in "todo_projects",
        on: tp.todo_id == t.id,
        where: tp.project_id == ^project_id,
        order_by: [
          asc: fragment("CASE WHEN ? THEN 0 ELSE 1 END", t.current),
          asc: fragment("CASE ? WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END", t.priority),
          desc: t.inserted_at
        ],
        preload: [:projects]

    Repo.all(query)
  end

  defp priority_class("high"), do: "bg-red-100 text-red-800"
  defp priority_class("medium"), do: "bg-yellow-100 text-yellow-800"
  defp priority_class("low"), do: "bg-green-100 text-green-800"
  defp priority_class(_), do: "bg-gray-100 text-gray-800"
end
