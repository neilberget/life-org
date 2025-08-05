defmodule LifeOrg.AIHandler do
  alias LifeOrg.{AnthropicClient, Repo, Todo, WorkspaceService}

  def process_message(message, journal_entries, conversation_history \\ []) do
    IO.puts("Building system prompt...")
    system_prompt = build_system_prompt(journal_entries)
    IO.puts("System prompt built: #{String.length(system_prompt)} characters")
    
    # Combine conversation history with new message
    messages = conversation_history ++ [%{role: "user", content: message}]
    IO.puts("Total messages in conversation: #{length(messages)}")
    
    IO.puts("Sending message to Anthropic API...")
    case AnthropicClient.send_message(messages, system_prompt) do
      {:ok, response} ->
        IO.puts("Got response from API: #{inspect(response)}")
        assistant_message = extract_assistant_message(response)
        tool_actions = parse_tool_actions(assistant_message)
        
        {:ok, assistant_message, tool_actions}
        
      {:error, error} ->
        IO.puts("API error: #{inspect(error)}")
        {:error, "Sorry, I encountered an error: #{error}"}
    end
  end

  def extract_todos_from_journal(journal_content, existing_todos \\ []) do
    existing_todos_context = case existing_todos do
      [] -> "No existing todos."
      todos ->
        todos
        |> Enum.map(fn todo ->
          status = if todo.completed, do: "[COMPLETED]", else: "[PENDING]"
          "#{status} ID: #{todo.id} | #{todo.title} (#{todo.priority})" <>
          if todo.description && String.trim(todo.description) != "", do: " - #{todo.description}", else: ""
        end)
        |> Enum.join("\n")
    end

    system_prompt = """
    You are a helpful assistant that manages todos based on journal entries.
    
    EXISTING TODOS:
    #{existing_todos_context}
    
    Analyze the journal entry and:
    1. Identify any NEW actionable tasks that aren't already covered by existing todos
    2. Identify any updates needed to existing todos (priority changes, additional details, completion status)
    3. Avoid creating duplicates - if a similar task already exists, update it instead
    
    Use these formats:
    - For NEW todos: [CREATE_TODO: title="Task title" description="Optional description" priority="high|medium|low"]
    - For UPDATING existing todos: [UPDATE_TODO: id=123 title="Updated title" description="Updated description" priority="high|medium|low"]
    - For COMPLETING todos: [COMPLETE_TODO: id=123]
    
    Guidelines for priority:
    - High: Urgent tasks, deadlines, important meetings
    - Medium: Regular tasks, planning items, follow-ups  
    - Low: Ideas, someday items, optional tasks
    
    Be smart about updates:
    - If journal mentions urgency/deadlines for existing tasks, increase priority
    - If journal provides more details about existing tasks, update description
    - If journal indicates task is done, mark as complete
    - Only create new todos for genuinely new actionable items
    """
    
    messages = [%{role: "user", content: journal_content}]
    
    case AnthropicClient.send_message(messages, system_prompt) do
      {:ok, response} ->
        assistant_message = extract_assistant_message(response)
        tool_actions = parse_tool_actions(assistant_message)
        {:ok, tool_actions}
        
      {:error, error} ->
        IO.puts("AI error extracting todos: #{inspect(error)}")
        {:ok, []}
    end
  end
  
  defp build_system_prompt(journal_entries) do
    recent_entries = Enum.take(journal_entries, 5)
    entries_context = Enum.map_join(recent_entries, "\n\n", fn entry ->
      "Date: #{Calendar.strftime(entry.inserted_at, "%B %d, %Y")}\nMood: #{entry.mood || "N/A"}\nContent: #{entry.content}"
    end)
    
    """
    You are a helpful life organization assistant. You have access to the user's journal entries and can help them manage their todos.
    
    Recent journal entries:
    #{entries_context}
    
    You can create todos by using the following format in your response:
    [CREATE_TODO: title="Task title" description="Optional description" priority="high|medium|low"]
    
    You can mark todos as complete by using:
    [COMPLETE_TODO: id=123]
    
    Be supportive, empathetic, and help the user organize their thoughts and tasks based on their journal entries.
    """
  end
  
  defp extract_assistant_message(response) do
    case response["content"] do
      [%{"text" => text} | _] -> text
      _ -> "I couldn't process that response."
    end
  end
  
  defp parse_tool_actions(text) do
    create_todos = parse_create_todos(text)
    update_todos = parse_update_todos(text)
    complete_todos = parse_complete_todos(text)
    
    create_todos ++ update_todos ++ complete_todos
  end
  
  defp parse_create_todos(text) do
    regex = ~r/\[CREATE_TODO: title="([^"]+)"(?:\s+description="([^"]+)")?(?:\s+priority="(high|medium|low)")?\]/
    
    Regex.scan(regex, text)
    |> Enum.map(fn [_, title, description, priority] ->
      %{
        action: :create_todo,
        title: title,
        description: description || "",
        priority: priority || "medium"
      }
    end)
  end
  
  defp parse_complete_todos(text) do
    regex = ~r/\[COMPLETE_TODO: id=(\d+)\]/
    
    Regex.scan(regex, text)
    |> Enum.map(fn [_, id] ->
      %{
        action: :complete_todo,
        id: String.to_integer(id)
      }
    end)
  end
  
  defp parse_update_todos(text) do
    regex = ~r/\[UPDATE_TODO: id=(\d+)(?:\s+title="([^"]+)")?(?:\s+description="([^"]+)")?(?:\s+priority="(high|medium|low)")?\]/
    
    Regex.scan(regex, text)
    |> Enum.map(fn [_, id, title, description, priority] ->
      updates = %{}
      |> maybe_add("title", title)
      |> maybe_add("description", description)
      |> maybe_add("priority", priority)
      
      %{
        action: :update_todo,
        id: String.to_integer(id),
        updates: updates
      }
    end)
  end
  
  defp maybe_add(map, _key, value) when value == "" or is_nil(value), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
  
  def execute_tool_action(%{action: :create_todo} = params, workspace_id) do
    WorkspaceService.create_todo(%{
      "title" => params.title,
      "description" => params.description,
      "priority" => params.priority,
      "ai_generated" => true
    }, workspace_id)
  end
  
  def execute_tool_action(%{action: :update_todo, id: id, updates: updates}, _workspace_id) do
    case Repo.get(Todo, id) do
      nil -> {:error, "Todo not found"}
      todo ->
        WorkspaceService.update_todo(todo, updates)
    end
  end
  
  def execute_tool_action(%{action: :complete_todo, id: id}, _workspace_id) do
    case Repo.get(Todo, id) do
      nil -> {:error, "Todo not found"}
      todo ->
        WorkspaceService.update_todo(todo, %{"completed" => true})
    end
  end
end