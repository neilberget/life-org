defmodule LifeOrg.AIHandler do
  alias LifeOrg.{AnthropicClient, Repo, Todo, WorkspaceService}

  def process_message(message, journal_entries, todos, conversation_history \\ []) do
    IO.puts("Building system prompt...")
    system_prompt = build_system_prompt(journal_entries, todos)
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
    # Get existing tags for context
    existing_tags = get_unique_tags(existing_todos)
    tags_context = case existing_tags do
      [] -> "No existing tags."
      tags -> "Existing tags: " <> Enum.join(tags, ", ")
    end
    
    existing_todos_context = case existing_todos do
      [] -> "No existing todos."
      todos ->
        todos
        |> Enum.map(fn todo ->
          status = if todo.completed, do: "[COMPLETED]", else: "[PENDING]"
          tags_info = case todo.tags do
            nil -> ""
            [] -> ""
            tags -> " [Tags: " <> Enum.join(tags, ", ") <> "]"
          end
          "#{status} ID: #{todo.id} | #{todo.title} (#{todo.priority})#{tags_info}" <>
          if todo.description && String.trim(todo.description) != "", do: " - #{todo.description}", else: ""
        end)
        |> Enum.join("\n")
    end

    system_prompt = """
    You are a helpful assistant that manages todos based on journal entries.
    
    EXISTING TODOS:
    #{existing_todos_context}
    
    #{tags_context}
    
    Analyze the journal entry and:
    1. Identify any NEW actionable tasks that aren't already covered by existing todos
    2. Identify any updates needed to existing todos (priority changes, additional details, completion status, tags)
    3. Avoid creating duplicates - if a similar task already exists, update it instead
    
    Use these formats:
    - For NEW todos: [CREATE_TODO: title="Task title" description="Optional description" priority="high|medium|low" tags="tag1, tag2, tag3"]
    - For UPDATING existing todos: [UPDATE_TODO: id=123 title="Updated title" description="Updated description" priority="high|medium|low" tags="tag1, tag2, tag3"]
    - For COMPLETING todos: [COMPLETE_TODO: id=123]
    
    Guidelines for priority:
    - High: Urgent tasks, deadlines, important meetings
    - Medium: Regular tasks, planning items, follow-ups  
    - Low: Ideas, someday items, optional tasks
    
    Guidelines for tags:
    - Use existing tags when applicable to maintain consistency
    - Suggest relevant new tags based on the task context (work, personal, urgent, project, store, health, etc.)
    - Consider the content of the journal entry to infer appropriate categorizations
    
    Be smart about updates:
    - If journal mentions urgency/deadlines for existing tasks, increase priority
    - If journal provides more details about existing tasks, update description
    - If journal indicates task is done, mark as complete
    - Add or update tags based on new context from journal entry
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
  
  defp build_system_prompt(journal_entries, todos) do
    recent_entries = Enum.take(journal_entries, 5)
    entries_context = Enum.map_join(recent_entries, "\n\n", fn entry ->
      "Date: #{Calendar.strftime(entry.inserted_at, "%B %d, %Y")}\nMood: #{entry.mood || "N/A"}\nContent: #{entry.content}"
    end)
    
    # Get existing tags for context
    existing_tags = get_unique_tags(todos)
    tags_context = case existing_tags do
      [] -> "No existing tags."
      tags -> "Existing tags: " <> Enum.join(tags, ", ")
    end
    
    todos_context = case todos do
      [] -> "No current todos."
      _ -> 
        sorted_todos = Enum.sort_by(todos, &({&1.completed, &1.priority != "high"}))
        Enum.map_join(sorted_todos, "\n", fn todo ->
          status = if todo.completed, do: "✓ COMPLETED", else: "○ PENDING"
          due_info = case {todo.due_date, todo.due_time} do
            {nil, _} -> ""
            {date, nil} -> " (Due: #{date})"
            {date, time} -> " (Due: #{date} #{time})"
          end
          priority = String.upcase(todo.priority || "medium")
          tags_info = case todo.tags do
            nil -> ""
            [] -> ""
            tags -> " [Tags: " <> Enum.join(tags, ", ") <> "]"
          end
          "#{status} [#{priority}] #{todo.title}#{due_info}#{tags_info}" <> 
            if todo.description && String.trim(todo.description) != "", do: " - #{todo.description}", else: ""
        end)
    end
    
    """
    You are a helpful life organization assistant. You have access to the user's journal entries and current todos. You can help them manage their tasks and reflect on their life.
    
    Recent journal entries:
    #{entries_context}
    
    Current todos:
    #{todos_context}
    
    #{tags_context}
    
    You can create todos by using the following format in your response:
    [CREATE_TODO: title="Task title" description="Optional description" priority="high|medium|low" tags="tag1, tag2, tag3"]
    
    You can mark todos as complete by using:
    [COMPLETE_TODO: id=123]
    
    When creating todos, please suggest appropriate tags based on:
    - Existing tags that are relevant to the new task
    - Common categorizations like "work", "personal", "urgent", "project", "store", "health", etc.
    - Context from the user's message or journal entries
    
    Use existing tags when possible to maintain consistency, but feel free to suggest new tags when appropriate.
    
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
    regex = ~r/\[CREATE_TODO: title="([^"]+)"(?:\s+description="([^"]+)")?(?:\s+priority="(high|medium|low)")?(?:\s+tags="([^"]+)")?\]/
    
    Regex.scan(regex, text)
    |> Enum.map(fn [_, title, description, priority, tags] ->
      parsed_tags = parse_tags_string(tags)
      %{
        action: :create_todo,
        title: title,
        description: description || "",
        priority: priority || "medium",
        tags: parsed_tags
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
    regex = ~r/\[UPDATE_TODO: id=(\d+)(?:\s+title="([^"]+)")?(?:\s+description="([^"]+)")?(?:\s+priority="(high|medium|low)")?(?:\s+tags="([^"]+)")?\]/
    
    Regex.scan(regex, text)
    |> Enum.map(fn [_, id, title, description, priority, tags] ->
      updates = %{}
      |> maybe_add("title", title)
      |> maybe_add("description", description)
      |> maybe_add("priority", priority)
      |> maybe_add_tags("tags", tags)
      
      %{
        action: :update_todo,
        id: String.to_integer(id),
        updates: updates
      }
    end)
  end
  
  defp maybe_add(map, _key, value) when value == "" or is_nil(value), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
  
  defp maybe_add_tags(map, _key, value) when value == "" or is_nil(value), do: map
  defp maybe_add_tags(map, key, value), do: Map.put(map, key, parse_tags_string(value))
  
  defp parse_tags_string(nil), do: []
  defp parse_tags_string(""), do: []
  defp parse_tags_string(tags_string) do
    tags_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end
  
  defp get_unique_tags(todos) do
    todos
    |> Enum.flat_map(fn todo -> todo.tags || [] end)
    |> Enum.uniq()
    |> Enum.sort()
  end
  
  def execute_tool_action(%{action: :create_todo} = params, workspace_id) do
    WorkspaceService.create_todo(%{
      "title" => params.title,
      "description" => params.description,
      "priority" => params.priority,
      "tags" => params.tags || [],
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