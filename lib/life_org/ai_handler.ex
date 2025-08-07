defmodule LifeOrg.AIHandler do
  import Ecto.Query
  alias LifeOrg.{AnthropicClient, Repo, Todo, WorkspaceService}

  def process_message(message, journal_entries, todos, conversation_history \\ [], workspace_id) do
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
        
        # If there are tool uses, execute them and get final response
        if length(tool_uses) > 0 do
          execute_tools_and_continue(messages, system_prompt, tools, content_blocks, tool_uses, workspace_id)
        else
          # No tools used, return the response directly
          {:ok, assistant_message, []}
        end
        
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
    You are a helpful assistant that extracts actionable todos from journal entries.
    
    EXISTING TODOS:
    #{existing_todos_context}
    
    #{tags_context}
    
    Create separate todos for each actionable task mentioned in the journal entry. Use multiple create_todo tool calls - one for each task.
    
    For each todo:
    - Use a clear, descriptive title
    - Set appropriate priority (high/medium/low)
    - Add relevant tags for categorization
    - Include description if the journal provides additional context
    - For complex tasks with subtasks, you can include GitHub-style markdown checkboxes in the description (- [ ] unchecked, - [x] checked) that will become interactive in the UI
    
    Only create new todos for tasks that don't already exist in the existing todos list above.
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
    - The user asks you to create, update, complete, or delete tasks
    - You need current information from the internet to provide helpful advice or context
    - The user asks questions that require up-to-date information beyond your knowledge cutoff
    
    When creating todos, please suggest appropriate tags based on:
    - Existing tags that are relevant to the new task
    - Common categorizations like "work", "personal", "urgent", "project", "store", "health", etc.
    - Context from the user's message or journal entries
    
    Use existing tags when possible to maintain consistency, but feel free to suggest new tags when appropriate.
    
    SUBTASK FORMATTING: When creating todo descriptions with subtasks, you can use GitHub-style markdown checkboxes that will become interactive:
    - Use `- [ ]` for unchecked subtasks
    - Use `- [x]` for checked subtasks
    These will render as clickable checkboxes in the UI for easy progress tracking.
    
    Be supportive, empathetic, and help the user organize their thoughts and tasks based on their journal entries. Use web search to provide current, relevant information when it would be helpful for their goals and tasks.
    """
  end
  
  defp build_tools_definition(todos) do
    # Get existing tags for the enum values
    existing_tags = get_unique_tags(todos)
    
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
              "description" => "Optional description with more details. You can include GitHub-style markdown checkboxes (- [ ] unchecked, - [x] checked) for subtasks that will become interactive in the UI."
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
              "description" => "The ID of the todo to update"
            },
            "title" => %{
              "type" => "string",
              "description" => "New title for the todo"
            },
            "description" => %{
              "type" => "string",
              "description" => "New description for the todo. You can include GitHub-style markdown checkboxes (- [ ] unchecked, - [x] checked) for subtasks that will become interactive in the UI."
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
              "description" => "The ID of the todo to complete"
            }
          },
          "required" => ["id"]
        }
      },
      %{
        "name" => "delete_todo",
        "description" => "Delete a todo permanently",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{
              "type" => "integer",
              "description" => "The ID of the todo to delete"
            }
          },
          "required" => ["id"]
        }
      },
      %{
        "name" => "get_todo_by_id",
        "description" => "Get details of a specific todo by ID or URL",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "id_or_url" => %{
              "type" => "string",
              "description" => "Either a numeric todo ID (e.g., '42') or a todo URL (e.g., 'http://localhost:4000/todo/42')"
            }
          },
          "required" => ["id_or_url"]
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
        
      "delete_todo" ->
        %{
          action: :delete_todo,
          id: tool_use.input["id"]
        }
        
      "get_todo_by_id" ->
        %{
          action: :get_todo_by_id,
          id_or_url: tool_use.input["id_or_url"]
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
      nil -> 
        {:error, "Todo not found"}
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
  
  def execute_tool_action(%{action: :delete_todo, id: id}, _workspace_id) do
    case Repo.get(Todo, id) do
      nil -> {:error, "Todo not found"}
      todo ->
        WorkspaceService.delete_todo(todo)
    end
  end

  def execute_tool_action(%{action: :get_todo_by_id, id_or_url: id_or_url}, workspace_id) do
    # Parse ID from either a direct ID or URL
    case parse_todo_id(id_or_url) do
      {:ok, todo_id} -> 
        get_todo_by_parsed_id(todo_id, workspace_id)
      {:error, reason} -> 
        {:error, reason}
    end
  end

  defp get_todo_by_parsed_id(todo_id, workspace_id) do
    case Repo.get(Todo, todo_id) do
      nil -> 
        {:error, "Todo not found with ID: #{todo_id}"}
      todo ->
        # Verify todo belongs to workspace
        if todo.workspace_id == workspace_id do
          # Load comments for full details
          comments = Repo.all(
            from c in LifeOrg.TodoComment,
            where: c.todo_id == ^todo_id,
            order_by: [asc: c.inserted_at]
          )
          {:ok, format_todo_for_ai(todo, comments)}
        else
          {:error, "Todo not found in current workspace"}
        end
    end
  end

  def process_todo_message(message, todo, todo_comments, all_todos, journal_entries, conversation_history \\ [], workspace_id) do
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
        
        # If there are tool uses, execute them and get final response
        if length(tool_uses) > 0 do
          IO.puts("Found #{length(tool_uses)} tool uses, executing...")
          try do
            execute_todo_tools_and_continue(messages, system_prompt, tools, content_blocks, tool_uses, workspace_id, todo, all_todos)
          rescue
            error ->
              IO.puts("Error in execute_todo_tools_and_continue: #{inspect(error)}")
              IO.puts("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
              {:error, "Tool execution failed: #{inspect(error)}"}
          end
        else
          # No tools used, return the response directly
          {:ok, assistant_message, []}
        end
        
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

    SUBTASK FORMATTING: When updating or creating todo descriptions with subtasks, you can use GitHub-style markdown checkboxes that will become interactive:
    - Use `- [ ]` for unchecked subtasks
    - Use `- [x]` for checked subtasks
    These will render as clickable checkboxes in the UI for easy progress tracking.

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
              "description" => "Optional description with more details. You can include GitHub-style markdown checkboxes (- [ ] unchecked, - [x] checked) for subtasks that will become interactive in the UI."
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
              "description" => "New description for the todo. You can include GitHub-style markdown checkboxes (- [ ] unchecked, - [x] checked) for subtasks that will become interactive in the UI."
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
      },
      %{
        "name" => "get_todo_by_id",
        "description" => "Get details of a specific todo by ID or URL",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "id_or_url" => %{
              "type" => "string",
              "description" => "Either a numeric todo ID (e.g., '42') or a todo URL (e.g., 'http://localhost:4000/todo/42')"
            }
          },
          "required" => ["id_or_url"]
        }
      }
    ]
  end

  defp convert_todo_tool_use_to_action(tool_use, current_todo, _all_todos) do
    
    result = case tool_use.name do
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
        
      "get_todo_by_id" ->
        %{
          action: :get_todo_by_id,
          id_or_url: tool_use.input["id_or_url"]
        }
    end
    
    result
  end

  defp execute_tools_and_continue(messages, system_prompt, tools, content_blocks, tool_uses, workspace_id) do
    IO.puts("Executing #{length(tool_uses)} tools...")
    
    # Execute each tool and collect results
    tool_results = Enum.map(tool_uses, fn tool_use ->
      IO.puts("Executing tool: #{tool_use.name}")
      
      # Convert to action and execute
      action = convert_tool_use_to_action(tool_use, [], nil)
      result = case execute_tool_action(action, workspace_id) do
        {:ok, result_data} when is_binary(result_data) ->
          result_data
        {:ok, _} ->
          "Tool executed successfully"
        {:error, error} ->
          "Error: #{error}"
      end
      
      # Build tool result message
      AnthropicClient.build_tool_result_message(tool_use.id, result)
    end)
    
    # Add assistant message (with tool calls) to conversation
    assistant_message_with_tools = %{
      role: "assistant", 
      content: content_blocks
    }
    
    # Continue conversation with tool results
    updated_messages = messages ++ [assistant_message_with_tools] ++ tool_results
    
    IO.puts("Sending tool results back to API...")
    case AnthropicClient.send_message(updated_messages, system_prompt, tools) do
      {:ok, final_response} ->
        IO.puts("Got final response from API")
        final_content_blocks = AnthropicClient.extract_content_from_response(final_response)
        final_message = AnthropicClient.extract_text_from_content(final_content_blocks)
        
        # Convert tool actions for UI updates (no tool IDs needed for this)
        tool_actions = Enum.map(tool_uses, &convert_tool_use_to_action(&1, []))
        
        {:ok, final_message, tool_actions}
        
      {:error, error} ->
        IO.puts("Error getting final response: #{inspect(error)}")
        {:error, "Sorry, I encountered an error processing the tool results: #{error}"}
    end
  end

  defp execute_todo_tools_and_continue(messages, system_prompt, tools, content_blocks, tool_uses, workspace_id, todo, all_todos) do
    # Execute each tool and collect results
    tool_results = Enum.map(tool_uses, fn tool_use ->
      # Convert to action and execute
      action = convert_todo_tool_use_to_action(tool_use, todo, all_todos)
      
      result = case execute_tool_action(action, workspace_id) do
        {:ok, result_data} when is_binary(result_data) ->
          result_data
        {:ok, _result_data} ->
          "Tool executed successfully"
        {:error, error} ->
          "Error: #{error}"
      end
      
      # Build tool result message
      AnthropicClient.build_tool_result_message(tool_use.id, result)
    end)
    
    # Add assistant message (with tool calls) to conversation
    assistant_message_with_tools = %{
      role: "assistant", 
      content: content_blocks
    }
    
    # Continue conversation with tool results
    updated_messages = messages ++ [assistant_message_with_tools] ++ tool_results
    
    case AnthropicClient.send_message(updated_messages, system_prompt, tools) do
      {:ok, final_response} ->
        final_content_blocks = AnthropicClient.extract_content_from_response(final_response)
        
        # Check if the final response contains more tools to execute
        final_tool_uses = AnthropicClient.extract_tool_uses_from_content(final_content_blocks)
        
        if length(final_tool_uses) > 0 do
          # Recursively handle additional tools
          execute_todo_tools_and_continue(updated_messages, system_prompt, tools, final_content_blocks, final_tool_uses, workspace_id, todo, all_todos)
        else
          # No more tools, extract final message
          final_message = AnthropicClient.extract_text_from_content(final_content_blocks)
          
          # Convert tool actions for UI updates (no tool IDs needed for this)
          tool_actions = Enum.map(tool_uses, &convert_todo_tool_use_to_action(&1, todo, all_todos))
          
          {:ok, final_message, tool_actions}
        end
        
      {:error, error} ->
        {:error, "Sorry, I encountered an error processing the tool results: #{error}"}
    end
  end

  defp parse_todo_id(id_or_url) do
    cond do
      # Check if it's a direct integer ID
      Regex.match?(~r/^\d+$/, String.trim(id_or_url)) ->
        case Integer.parse(String.trim(id_or_url)) do
          {id, ""} -> {:ok, id}
          _ -> {:error, "Invalid todo ID format"}
        end
        
      # Check if it's a URL pattern like http://localhost:4000/todo/42
      Regex.match?(~r/\/todo\/(\d+)/, id_or_url) ->
        case Regex.run(~r/\/todo\/(\d+)/, id_or_url) do
          [_, id_str] ->
            case Integer.parse(id_str) do
              {id, ""} -> {:ok, id}
              _ -> {:error, "Invalid todo ID in URL"}
            end
          _ -> {:error, "Could not extract todo ID from URL"}
        end
        
      true ->
        {:error, "Invalid format. Expected either a numeric ID (e.g., '42') or a todo URL (e.g., 'http://localhost:4000/todo/42')"}
    end
  end

  defp format_todo_for_ai(todo, comments) do
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

    comments_section = format_todo_comments_for_ai(comments)
    
    """
    Todo Details:
    ID: #{todo.id} | #{status} | Priority: #{priority} | Title: #{todo.title}#{due_info}#{tags_info}#{description}
    
    Created: #{Calendar.strftime(todo.inserted_at, "%B %d, %Y at %I:%M %p")}
    Last Updated: #{Calendar.strftime(todo.updated_at, "%B %d, %Y at %I:%M %p")}

    #{comments_section}
    """
  end

  defp format_todo_comments_for_ai(comments) do
    case comments do
      [] -> "Comments: No comments yet on this todo."
      _ ->
        formatted_comments = Enum.map_join(comments, "\n\n", fn comment ->
          date = Calendar.strftime(comment.inserted_at, "%B %d, %Y at %I:%M %p")
          "#{date}: #{comment.content}"
        end)
        "Comments:\n#{formatted_comments}"
    end
  end
end