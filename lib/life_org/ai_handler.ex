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

  def extract_todos_from_journal(journal_content, existing_todos \\ [], journal_entry_id \\ nil) do
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
        tool_actions = Enum.map(tool_uses, &convert_tool_use_to_action(&1, existing_todos, journal_entry_id))
        {:ok, tool_actions}
        
      {:error, error} ->
        IO.puts("AI error extracting todos: #{inspect(error)}")
        {:ok, []}
    end
  end
  
  defp build_system_prompt(journal_entries, todos) do
    recent_entries = Enum.take(journal_entries, 5)
    entries_context = Enum.map_join(recent_entries, "\n\n", fn entry ->
      "Date: #{Calendar.strftime(entry.inserted_at, "%B %d, %Y")}\nContent: #{entry.content}"
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
    
    You have access to tools for managing todos and web search capabilities. Use these tools when:
    - The user asks you to create, update, or complete tasks
    - You need current information from the internet to provide helpful advice or context
    - The user asks questions that require up-to-date information beyond your knowledge cutoff
    
    When creating todos, please suggest appropriate tags based on:
    - Existing tags that are relevant to the new task
    - Common categorizations like "work", "personal", "urgent", "project", "store", "health", etc.
    - Context from the user's message or journal entries
    
    Use existing tags when possible to maintain consistency, but feel free to suggest new tags when appropriate.
    
    Be supportive, empathetic, and help the user organize their thoughts and tasks based on their journal entries. Use web search to provide current, relevant information when it would be helpful for their goals and tasks.
    """
  end
  
  defp build_tools_definition(todos) do
    # Get existing tags for the enum values
    existing_tags = get_unique_tags(todos)
    
    # Build todo IDs list for update/complete tools
    todo_ids = Enum.map(todos, & &1.id)
    
    [
      %{
        "type" => "web_search_20250305",
        "name" => "web_search",
        "max_uses" => 5
      },
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
  
  defp convert_tool_use_to_action(tool_use, _todos, journal_entry_id \\ nil) do
    case tool_use.name do
      "create_todo" ->
        %{
          action: :create_todo,
          title: tool_use.input["title"],
          description: tool_use.input["description"] || "",
          priority: tool_use.input["priority"] || "medium",
          tags: tool_use.input["tags"] || [],
          journal_entry_id: journal_entry_id
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
  defp maybe_add(map, key, value) when is_list(value) and value != [], do: Map.put(map, key, value)
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
  
  defp get_unique_tags(todos) do
    todos
    |> Enum.flat_map(fn todo -> todo.tags || [] end)
    |> Enum.uniq()
    |> Enum.sort()
  end
  
  def execute_tool_action(%{action: :create_todo} = params, workspace_id) do
    todo_attrs = %{
      "title" => params.title,
      "description" => params.description,
      "priority" => params.priority,
      "tags" => params.tags || [],
      "ai_generated" => true
    }
    
    # Add journal_entry_id if present
    todo_attrs = if params[:journal_entry_id] do
      Map.put(todo_attrs, "journal_entry_id", params.journal_entry_id)
    else
      todo_attrs
    end
    
    WorkspaceService.create_todo(todo_attrs, workspace_id)
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

  def process_todo_message(message, todo, todo_comments, all_todos, journal_entries, conversation_history \\ []) do
    IO.puts("Building todo-specific system prompt...")
    system_prompt = build_todo_system_prompt(todo, todo_comments, all_todos, journal_entries)
    IO.puts("Todo system prompt built: #{String.length(system_prompt)} characters")
    
    # Define available tools for todo conversations
    tools = build_todo_tools_definition(todo, all_todos)
    
    # Combine conversation history with new message
    messages = conversation_history ++ [%{role: "user", content: message}]
    IO.puts("Total messages in todo conversation: #{length(messages)}")
    
    IO.puts("Sending todo message to Anthropic API...")
    case AnthropicClient.send_message(messages, system_prompt, tools) do
      {:ok, response} ->
        IO.puts("Got response from API: #{inspect(response)}")
        content_blocks = AnthropicClient.extract_content_from_response(response)
        
        # Extract text message and tool uses separately
        assistant_message = AnthropicClient.extract_text_from_content(content_blocks)
        tool_uses = AnthropicClient.extract_tool_uses_from_content(content_blocks)
        
        # Convert tool uses to our action format for todo operations
        tool_actions = Enum.map(tool_uses, &convert_todo_tool_use_to_action(&1, todo, all_todos))
        
        {:ok, assistant_message, tool_actions}
        
      {:error, error} ->
        IO.puts("API error: #{inspect(error)}")
        {:error, "Sorry, I encountered an error: #{error}"}
    end
  end

  defp build_todo_system_prompt(todo, todo_comments, all_todos, journal_entries) do
    # Format the current todo details
    todo_details = format_todo_details(todo)
    
    # Format todo comments
    comments_context = format_todo_comments(todo_comments)
    
    # Find related todos (by tags or keywords)
    related_todos = find_related_todos(todo, all_todos)
    related_context = format_related_todos(related_todos)
    
    # Handle journal entries context with priority for originating entry
    entries_context = format_journal_entries_for_todo(todo, journal_entries)
    
    # Get existing tags for context
    existing_tags = get_unique_tags(all_todos)
    tags_context = case existing_tags do
      [] -> "No existing tags."
      tags -> "Available tags: " <> Enum.join(tags, ", ")
    end
    
    """
    You are a helpful personal assistant focused on helping with a specific todo item. You understand the user's broader life context but specialize in providing targeted advice, suggestions, and task management for the current todo.

    CURRENT TODO:
    #{todo_details}

    TODO COMMENTS & DISCUSSION:
    #{comments_context}

    RELATED TODOS:
    #{related_context}

    RECENT LIFE CONTEXT:
    #{entries_context}

    #{tags_context}

    You can help with:
    - Breaking down complex tasks into smaller steps
    - Providing suggestions and recommendations based on the todo content
    - Managing todo details (priority, tags, descriptions, due dates)
    - Offering contextual advice based on journal entries and previous comments
    - Creating related or follow-up todos
    - Understanding progress and obstacles from the comment history
    - Searching the web for current information, resources, or guidance related to the todo

    You have access to web search capabilities to find current information, tutorials, best practices, or resources that would help complete this todo effectively. Use web search when it would provide valuable, up-to-date information for accomplishing the task.

    Be supportive and provide actionable advice specific to this todo. Use the available tools when the user wants to modify the todo, create related tasks, or needs current information from the internet.
    """
  end

  defp format_todo_details(todo) do
    due_info = case {todo.due_date, todo.due_time} do
      {nil, _} -> ""
      {date, nil} -> " | Due: #{date}"
      {date, time} -> " | Due: #{date} at #{time}"
    end
    
    status = if todo.completed, do: "✓ COMPLETED", else: "○ PENDING"
    priority = String.upcase(todo.priority || "medium")
    
    tags_info = case todo.tags do
      nil -> ""
      [] -> ""
      tags -> " | Tags: " <> Enum.join(tags, ", ")
    end
    
    description = if todo.description && String.trim(todo.description) != "" do
      "\nDescription: #{todo.description}"
    else
      ""
    end
    
    """
    ID: #{todo.id} | #{status} | Priority: #{priority} | Title: #{todo.title}#{due_info}#{tags_info}#{description}
    """
  end

  defp format_todo_comments(comments) do
    case comments do
      [] -> "No comments yet on this todo."
      _ ->
        formatted_comments = Enum.map_join(comments, "\n\n", fn comment ->
          date = Calendar.strftime(comment.inserted_at, "%B %d, %Y at %I:%M %p")
          "#{date}: #{comment.content}"
        end)
        "Comment history:\n#{formatted_comments}"
    end
  end

  defp find_related_todos(target_todo, all_todos) do
    target_tags = target_todo.tags || []
    
    all_todos
    |> Enum.filter(fn todo -> 
      todo.id != target_todo.id && 
      todo.tags != nil && 
      length(todo.tags) > 0 &&
      Enum.any?(todo.tags, fn tag -> tag in target_tags end)
    end)
    |> Enum.take(5) # Limit to 5 most relevant
  end

  defp format_related_todos(related_todos) do
    case related_todos do
      [] -> "No related todos found."
      _ ->
        formatted = Enum.map_join(related_todos, "\n", fn todo ->
          status = if todo.completed, do: "✓", else: "○"
          priority = String.upcase(todo.priority || "medium")
          tags = if todo.tags, do: " [#{Enum.join(todo.tags, ", ")}]", else: ""
          "#{status} [#{priority}] #{todo.title}#{tags}"
        end)
        "Related todos:\n#{formatted}"
    end
  end

  defp format_journal_entries(entries) do
    case entries do
      [] -> "No recent journal entries."
      _ ->
        formatted = Enum.map_join(entries, "\n\n", fn entry ->
          date = Calendar.strftime(entry.inserted_at, "%B %d, %Y")
          "#{date}: #{String.slice(entry.content, 0, 200)}#{if String.length(entry.content) > 200, do: "...", else: ""}"
        end)
        "Recent journal entries:\n#{formatted}"
    end
  end

  defp format_journal_entries_for_todo(todo, journal_entries) do
    # Check if this todo has an originating journal entry
    originating_entry = if todo.journal_entry_id do
      # Find the originating entry in the provided entries or load it separately if needed
      Enum.find(journal_entries, fn entry -> entry.id == todo.journal_entry_id end) ||
        (Repo.get(LifeOrg.JournalEntry, todo.journal_entry_id))
    else
      nil
    end

    case {originating_entry, journal_entries} do
      {nil, []} -> 
        "No recent journal entries available."
        
      {nil, entries} ->
        # No originating entry, show recent entries normally
        recent_entries = Enum.take(entries, 3)
        format_journal_entries(recent_entries)
        
      {orig_entry, entries} ->
        # Prioritize originating entry, then show recent entries (excluding the originating one to avoid duplication)
        other_entries = entries 
        |> Enum.reject(fn entry -> entry.id == orig_entry.id end)
        |> Enum.take(2) # Take 2 since we'll include the originating entry

        formatted_orig = format_single_journal_entry(orig_entry, true)
        
        case other_entries do
          [] ->
            """
            ORIGINATING JOURNAL ENTRY (this todo was created from this entry):
            #{formatted_orig}
            """
            
          _ ->
            formatted_others = Enum.map_join(other_entries, "\n\n", &format_single_journal_entry(&1, false))
            """
            ORIGINATING JOURNAL ENTRY (this todo was created from this entry):
            #{formatted_orig}

            Other recent journal entries:
            #{formatted_others}
            """
        end
    end
  end

  defp format_single_journal_entry(entry, is_originating) do
    date = Calendar.strftime(entry.entry_date || entry.inserted_at, "%B %d, %Y")
    
    # For originating entry, show full content; for others, truncate as before
    content = if is_originating do
      entry.content
    else
      "#{String.slice(entry.content, 0, 200)}#{if String.length(entry.content) > 200, do: "...", else: ""}"
    end
    
    "#{date}: #{content}"
  end

  defp build_todo_tools_definition(_todo, all_todos) do
    existing_tags = get_unique_tags(all_todos)
    
    [
      %{
        "type" => "web_search_20250305",
        "name" => "web_search",
        "max_uses" => 5
      },
      %{
        "name" => "create_related_todo",
        "description" => "Create a new todo related to the current one",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "title" => %{
              "type" => "string",
              "description" => "The title of the new todo"
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
              "description" => "Tags to categorize the todo. Available tags: #{Enum.join(existing_tags, ", ")}"
            }
          },
          "required" => ["title"]
        }
      },
      %{
        "name" => "update_current_todo",
        "description" => "Update the current todo being discussed",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
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
            },
            "due_date" => %{
              "type" => "string",
              "format" => "date",
              "description" => "Due date in YYYY-MM-DD format"
            }
          },
          "required" => []
        }
      },
      %{
        "name" => "complete_current_todo",
        "description" => "Mark the current todo as completed",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "completion_note" => %{
              "type" => "string",
              "description" => "Optional note about the completion"
            }
          },
          "required" => []
        }
      }
    ]
  end

  defp convert_todo_tool_use_to_action(tool_use, current_todo, _all_todos) do
    case tool_use.name do
      "create_related_todo" ->
        %{
          action: :create_todo,
          title: tool_use.input["title"],
          description: tool_use.input["description"] || "",
          priority: tool_use.input["priority"] || "medium",
          tags: tool_use.input["tags"] || []
        }
        
      "update_current_todo" ->
        updates = %{}
        |> maybe_add("title", tool_use.input["title"])
        |> maybe_add("description", tool_use.input["description"])
        |> maybe_add("priority", tool_use.input["priority"])
        |> maybe_add("tags", tool_use.input["tags"])
        |> maybe_add("due_date", tool_use.input["due_date"])
        
        %{
          action: :update_todo,
          id: current_todo.id,
          updates: updates
        }
        
      "complete_current_todo" ->
        %{
          action: :complete_todo,
          id: current_todo.id,
          completion_note: tool_use.input["completion_note"]
        }
    end
  end
end