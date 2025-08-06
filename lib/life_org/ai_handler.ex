defmodule LifeOrg.AIHandler do
  alias LifeOrg.{AnthropicClient, Repo, Todo, WorkspaceService}

  def process_message(message, journal_entries, todos, conversation_history \\ []) do
    IO.puts("Building system prompt...")
    system_prompt = build_system_prompt(journal_entries, todos)
    IO.puts("System prompt built: #{String.length(system_prompt)} characters")
    
    # Define available tools
    tools = build_tools_definition(todos)
    
    # Combine conversation history with new message
    messages = conversation_history ++ [%{role: "user", content: message}]
    IO.puts("Total messages in conversation: #{length(messages)}")
    
    IO.puts("Sending message to Anthropic API with tools...")
    case AnthropicClient.send_message(messages, system_prompt, tools) do
      {:ok, response} ->
        IO.puts("Got response from API: #{inspect(response)}")
        content_blocks = AnthropicClient.extract_content_from_response(response)
        
        # Extract text message and tool uses separately
        assistant_message = AnthropicClient.extract_text_from_content(content_blocks)
        tool_uses = AnthropicClient.extract_tool_uses_from_content(content_blocks)
        
        # Convert tool uses to our action format
        tool_actions = Enum.map(tool_uses, &convert_tool_use_to_action(&1, todos))
        
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
    
    # Define tools for journal todo extraction
    tools = build_tools_definition(existing_todos)
    
    messages = [%{role: "user", content: journal_content}]
    
    case AnthropicClient.send_message(messages, system_prompt, tools) do
      {:ok, response} ->
        content_blocks = AnthropicClient.extract_content_from_response(response)
        tool_uses = AnthropicClient.extract_tool_uses_from_content(content_blocks)
        
        # Convert tool uses to our action format
        tool_actions = Enum.map(tool_uses, &convert_tool_use_to_action(&1, existing_todos))
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
          "ID: #{todo.id} | #{status} [#{priority}] #{todo.title}#{due_info}#{tags_info}" <> 
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
    
    You have access to tools for managing todos. Use them when the user asks you to create, update, or complete tasks.
    
    When creating todos, please suggest appropriate tags based on:
    - Existing tags that are relevant to the new task
    - Common categorizations like "work", "personal", "urgent", "project", "store", "health", etc.
    - Context from the user's message or journal entries
    
    Use existing tags when possible to maintain consistency, but feel free to suggest new tags when appropriate.
    
    Be supportive, empathetic, and help the user organize their thoughts and tasks based on their journal entries.
    """
  end
  
  defp build_tools_definition(todos) do
    # Get existing tags for the enum values
    existing_tags = get_unique_tags(todos)
    
    # Build todo IDs list for update/complete tools
    todo_ids = Enum.map(todos, & &1.id)
    
    [
      %{
        "name" => "create_todo",
        "description" => "Create a new todo item",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "title" => %{
              "type" => "string",
              "description" => "The title of the todo"
            },
            "description" => %{
              "type" => "string",
              "description" => "Optional description with more details"
            },
            "priority" => %{
              "type" => "string",
              "enum" => ["high", "medium", "low"],
              "description" => "Priority level of the todo"
            },
            "tags" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Tags to categorize the todo. Existing tags: #{Enum.join(existing_tags, ", ")}"
            }
          },
          "required" => ["title"]
        }
      },
      %{
        "name" => "update_todo",
        "description" => "Update an existing todo item",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{
              "type" => "integer",
              "description" => "The ID of the todo to update. Available IDs: #{Enum.join(todo_ids, ", ")}"
            },
            "title" => %{
              "type" => "string",
              "description" => "New title for the todo"
            },
            "description" => %{
              "type" => "string",
              "description" => "New description for the todo"
            },
            "priority" => %{
              "type" => "string",
              "enum" => ["high", "medium", "low"],
              "description" => "New priority level"
            },
            "tags" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "New tags for the todo"
            }
          },
          "required" => ["id"]
        }
      },
      %{
        "name" => "complete_todo",
        "description" => "Mark a todo as completed",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{
              "type" => "integer",
              "description" => "The ID of the todo to complete. Available IDs: #{Enum.join(todo_ids, ", ")}"
            }
          },
          "required" => ["id"]
        }
      }
    ]
  end
  
  defp convert_tool_use_to_action(tool_use, _todos) do
    case tool_use.name do
      "create_todo" ->
        %{
          action: :create_todo,
          title: tool_use.input["title"],
          description: tool_use.input["description"] || "",
          priority: tool_use.input["priority"] || "medium",
          tags: tool_use.input["tags"] || []
        }
        
      "update_todo" ->
        updates = %{}
        |> maybe_add("title", tool_use.input["title"])
        |> maybe_add("description", tool_use.input["description"])
        |> maybe_add("priority", tool_use.input["priority"])
        |> maybe_add("tags", tool_use.input["tags"])
        
        %{
          action: :update_todo,
          id: tool_use.input["id"],
          updates: updates
        }
        
      "complete_todo" ->
        %{
          action: :complete_todo,
          id: tool_use.input["id"]
        }
    end
  end
  
  defp maybe_add(map, _key, value) when value == "" or is_nil(value), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
  
  defp maybe_add(map, key, value) when is_list(value) and value != [], do: Map.put(map, key, value)
  
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