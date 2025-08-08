defmodule LifeOrg.AIHandler do
  import Ecto.Query
  alias LifeOrg.{AnthropicClient, EmbeddingsService, Repo, Todo, WorkspaceService}

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
    result = retry_with_backoff(fn ->
      AnthropicClient.send_message(messages, system_prompt, tools)
    end, max_retries: 2, retry_on: :timeout)
    
    case result do
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
        IO.puts("API error after retries: #{inspect(error)}")
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
    
    # Attempt with retries on timeout errors
    result = retry_with_backoff(fn ->
      AnthropicClient.send_message(messages, system_prompt, tools)
    end, max_retries: 2, retry_on: :timeout)
    
    case result do
      {:ok, response} ->
        content_blocks = AnthropicClient.extract_content_from_response(response)
        tool_uses = AnthropicClient.extract_tool_uses_from_content(content_blocks)
        
        # Convert tool uses to our action format
        tool_actions = Enum.map(tool_uses, &convert_tool_use_to_action(&1, existing_todos, journal_entry_id))
        {:ok, tool_actions}
        
      {:error, error} ->
        IO.puts("AI error extracting todos after retries: #{inspect(error)}")
        {:ok, []}
    end
  end
  
  # Helper function to retry API calls with exponential backoff
  defp retry_with_backoff(fun, opts) do
    max_retries = Keyword.get(opts, :max_retries, 2)
    retry_on = Keyword.get(opts, :retry_on, :timeout)
    
    do_retry(fun, 0, max_retries, retry_on)
  end
  
  defp do_retry(fun, attempt, max_retries, retry_on) do
    case fun.() do
      {:error, %Req.TransportError{reason: :timeout}} when attempt < max_retries and retry_on == :timeout ->
        # Calculate backoff delay (exponential backoff with base of 2 seconds)
        delay = round(:timer.seconds(2) * :math.pow(2, attempt))
        IO.puts("Timeout error on attempt #{attempt + 1}, retrying in #{delay}ms...")
        Process.sleep(delay)
        do_retry(fun, attempt + 1, max_retries, retry_on)
        
      {:error, "Network error: " <> rest} = error when attempt < max_retries ->
        # Also handle string-formatted network errors that might contain timeout info
        if String.contains?(rest, "timeout") and retry_on == :timeout do
          delay = round(:timer.seconds(2) * :math.pow(2, attempt))
          IO.puts("Network timeout error on attempt #{attempt + 1}, retrying in #{delay}ms...")
          Process.sleep(delay)
          do_retry(fun, attempt + 1, max_retries, retry_on)
        else
          error
        end
        
      result ->
        # Either success or non-retryable error or max retries reached
        result
    end
  end
  
  defp build_system_prompt(journal_entries, todos) do
    # Only include summary statistics and high-priority/current items to reduce token usage
    # The AI can use search_content tool to find relevant detailed content as needed
    
    journal_count = length(journal_entries)
    journal_summary = if journal_count > 0 do
      most_recent = List.first(journal_entries)
      recent_date = Calendar.strftime(most_recent.inserted_at, "%B %d, %Y")
      "#{journal_count} journal entries available. Most recent: #{recent_date}"
    else
      "No journal entries yet."
    end
    
    # Only show high priority todos and current/due soon items to reduce context
    high_priority_todos = Enum.filter(todos, &(&1.priority == "high" and not &1.completed))
    current_todos = Enum.filter(todos, &(&1.current and not &1.completed))
    due_soon_todos = Enum.filter(todos, fn todo ->
      case todo do
        %{completed: false, due_date: %Date{} = due_date} ->
          days_diff = Date.diff(due_date, Date.utc_today())
          days_diff <= 3 && days_diff >= -1
        _ -> 
          false
      end
    end)
    
    priority_context = format_priority_todos(high_priority_todos ++ current_todos ++ due_soon_todos)
    
    # Basic statistics for context
    total_todos = length(todos)
    completed_todos = Enum.count(todos, & &1.completed)
    pending_todos = total_todos - completed_todos
    
    todos_summary = "#{pending_todos} pending todos, #{completed_todos} completed"
    
    # Get existing tags for context (keep this as it's small and useful)
    existing_tags = get_unique_tags(todos)
    tags_context = case existing_tags do
      [] -> "No existing tags."
      tags -> "Available tags: " <> Enum.join(Enum.take(tags, 15), ", ") <> if length(tags) > 15, do: "...", else: ""
    end
    
    """
    You are a helpful life organization assistant. You can help users manage their tasks and reflect on their life using available tools.
    
    CONTENT OVERVIEW:
    - Journal: #{journal_summary}
    - Todos: #{todos_summary}
    - #{tags_context}
    
    HIGH PRIORITY & CURRENT ITEMS:
    #{priority_context}
    
    IMPORTANT: Use the search_content tool to find relevant journal entries or todos when you need specific context or past information. Don't guess about past content - search for it instead.
    
    You have access to tools for managing todos, semantic content search, and web search capabilities. Use these tools when:
    - The user asks you to create, update, complete, or delete tasks
    - You need to find relevant journal entries or todos based on semantic similarity (use search_content tool)
    - You need current information from the internet to provide helpful advice or context
    - The user asks questions that require up-to-date information beyond your knowledge cutoff
    - The user wants to find past entries or todos related to a specific topic or theme
    
    When creating todos, please suggest appropriate tags based on:
    - Existing tags that are relevant to the new task
    - Common categorizations like "work", "personal", "urgent", "project", "store", "health", etc.
    - Context from the user's message or journal entries
    
    Use existing tags when possible to maintain consistency, but feel free to suggest new tags when appropriate.
    
    SUBTASK FORMATTING: When creating todo descriptions with subtasks, you can use GitHub-style markdown checkboxes that will become interactive:
    - Use `- [ ]` for unchecked subtasks
    - Use `- [x]` for checked subtasks
    These will render as clickable checkboxes in the UI for easy progress tracking.
    
    The search_content tool performs semantic vector similarity search across journal entries and todos. Use it to find relevant past content when:
    - The user asks about previous discussions on a topic
    - You need more context about similar situations or themes
    - The user wants to see related journal entries or todos
    - You need to understand patterns in their past activities
    
    Be supportive, empathetic, and help the user organize their thoughts and tasks based on their journal entries. Use both semantic search for finding relevant past context and web search for current, relevant information when it would be helpful for their goals and tasks.
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
        "name" => "search_content",
        "description" => "Search journal entries and todos using semantic vector similarity to find the most relevant content",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "query" => %{
              "type" => "string",
              "description" => "The search query text to find relevant content"
            },
            "content_type" => %{
              "type" => "string",
              "enum" => ["all", "journal", "todo"],
              "description" => "Type of content to search: 'all' for both journal entries and todos, 'journal' for only journal entries, 'todo' for only todos"
            },
            "limit" => %{
              "type" => "integer",
              "minimum" => 1,
              "maximum" => 20,
              "description" => "Maximum number of results to return (default: 10)"
            },
            "date_from" => %{
              "type" => "string",
              "format" => "date",
              "description" => "Optional start date filter in YYYY-MM-DD format"
            },
            "date_to" => %{
              "type" => "string",
              "format" => "date",
              "description" => "Optional end date filter in YYYY-MM-DD format"
            },
            "todo_status" => %{
              "type" => "string",
              "enum" => ["all", "pending", "completed"],
              "description" => "For todo searches: 'all' for all todos, 'pending' for uncompleted, 'completed' for completed todos"
            }
          },
          "required" => ["query"]
        }
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
      "search_content" ->
        %{
          action: :search_content,
          query: tool_use.input["query"],
          content_type: tool_use.input["content_type"] || "all",
          limit: tool_use.input["limit"] || 10,
          date_from: tool_use.input["date_from"],
          date_to: tool_use.input["date_to"],
          todo_status: tool_use.input["todo_status"] || "all"
        }
        
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

  defp format_priority_todos(todos) do
    case Enum.uniq_by(todos, & &1.id) do
      [] -> "No high priority, current, or due soon todos."
      priority_todos ->
        formatted = Enum.map_join(priority_todos, "\n", fn todo ->
          status = if todo.completed, do: "✓", else: "○"
          priority = String.upcase(todo.priority || "medium")
          current_indicator = if todo.current, do: " [CURRENT]", else: ""
          
          due_info = case {todo.due_date, todo.due_time} do
            {nil, _} -> ""
            {date, nil} -> " (Due: #{date})"
            {date, time} -> " (Due: #{date} #{time})"
          end
          
          "#{status} [#{priority}] #{todo.title}#{current_indicator}#{due_info}"
        end)
        formatted
    end
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

  def execute_tool_action(%{action: :search_content} = params, workspace_id) do
    search_opts = [
      workspace_id: workspace_id,
      limit: params.limit
    ]

    # Apply date filtering if provided
    search_opts = if params.date_from || params.date_to do
      Keyword.put(search_opts, :date_from, params.date_from) |> Keyword.put(:date_to, params.date_to)
    else
      search_opts
    end

    # Apply todo status filtering if provided
    search_opts = if params.todo_status && params.todo_status != "all" do
      Keyword.put(search_opts, :todo_status, params.todo_status)
    else
      search_opts
    end

    case params.content_type do
      "journal" ->
        execute_journal_search(params.query, search_opts)
      "todo" ->
        execute_todo_search(params.query, search_opts)
      _ -> # "all" or any other value
        execute_combined_search(params.query, search_opts)
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
    result = retry_with_backoff(fn ->
      AnthropicClient.send_message(messages, system_prompt, tools)
    end, max_retries: 2, retry_on: :timeout)
    
    case result do
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
        IO.puts("API error after retries: #{inspect(error)}")
        {:error, "Sorry, I encountered an error: #{error}"}
    end
  end

  defp build_todo_system_prompt(todo, todo_comments, all_todos, journal_entries) do
    # Format the current todo details
    todo_details = format_todo_details(todo)
    
    # Format todo comments
    comments_context = format_todo_comments(todo_comments)
    
    # Handle journal entries context with priority for originating entry
    entries_context = format_journal_entries_for_todo(todo, journal_entries)
    
    # Get existing tags for context (limit to avoid token bloat)
    existing_tags = get_unique_tags(all_todos)
    tags_context = case existing_tags do
      [] -> "No existing tags."
      tags -> "Available tags: " <> Enum.join(Enum.take(tags, 15), ", ") <> if length(tags) > 15, do: "...", else: ""
    end
    
    """
    You are a helpful personal assistant focused on helping with a specific todo item. You understand the user's broader life context but specialize in providing targeted advice, suggestions, and task management for the current todo.

    CURRENT TODO:
    #{todo_details}

    TODO COMMENTS & DISCUSSION:
    #{comments_context}

    LIFE CONTEXT:
    #{entries_context}

    #{tags_context}

    You can help with:
    - Breaking down complex tasks into smaller steps
    - Providing suggestions and recommendations based on the todo content
    - Managing todo details (priority, tags, descriptions, due dates)
    - Offering contextual advice based on journal entries and previous comments
    - Creating related or follow-up todos
    - Understanding progress and obstacles from the comment history
    - Finding related past journal entries or todos using semantic search (search_content tool) - use this to discover patterns, similar tasks, or relevant context
    - Searching the web for current information, resources, or guidance related to the todo

    SUBTASK FORMATTING: When updating or creating todo descriptions with subtasks, you can use GitHub-style markdown checkboxes that will become interactive:
    - Use `- [ ]` for unchecked subtasks
    - Use `- [x]` for checked subtasks
    These will render as clickable checkboxes in the UI for easy progress tracking.

    You have access to both semantic search (search_content tool) and web search capabilities. Use semantic search to find relevant past journal entries or todos that might provide context, patterns, or related experiences. Use web search when you need current information, tutorials, best practices, or resources that would help complete this todo effectively.

    Be supportive and provide actionable advice specific to this todo. Use the available tools when the user wants to modify the todo, create related tasks, needs context from past activities, or requires current information from the internet.
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



  defp format_journal_entries_for_todo(todo, journal_entries) do
    # Only include the originating journal entry if it exists, since AI can search for other relevant entries
    if todo.journal_entry_id do
      # Find the originating entry
      originating_entry = Enum.find(journal_entries, fn entry -> entry.id == todo.journal_entry_id end) ||
        (Repo.get(LifeOrg.JournalEntry, todo.journal_entry_id))
      
      if originating_entry do
        formatted_orig = format_single_journal_entry(originating_entry, true)
        """
        ORIGINATING JOURNAL ENTRY (this todo was created from this entry):
        #{formatted_orig}
        
        Use search_content tool to find other relevant journal entries as needed.
        """
      else
        "This todo was created from a journal entry, but it's not currently available. Use search_content tool to find relevant entries."
      end
    else
      journal_count = length(journal_entries)
      if journal_count > 0 do
        "#{journal_count} journal entries available. Use search_content tool to find entries relevant to this todo."
      else
        "No journal entries available."
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
        "name" => "search_content",
        "description" => "Search journal entries and todos using semantic vector similarity to find the most relevant content",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "query" => %{
              "type" => "string",
              "description" => "The search query text to find relevant content"
            },
            "content_type" => %{
              "type" => "string",
              "enum" => ["all", "journal", "todo"],
              "description" => "Type of content to search: 'all' for both journal entries and todos, 'journal' for only journal entries, 'todo' for only todos"
            },
            "limit" => %{
              "type" => "integer",
              "minimum" => 1,
              "maximum" => 20,
              "description" => "Maximum number of results to return (default: 10)"
            },
            "date_from" => %{
              "type" => "string",
              "format" => "date",
              "description" => "Optional start date filter in YYYY-MM-DD format"
            },
            "date_to" => %{
              "type" => "string",
              "format" => "date",
              "description" => "Optional end date filter in YYYY-MM-DD format"
            },
            "todo_status" => %{
              "type" => "string",
              "enum" => ["all", "pending", "completed"],
              "description" => "For todo searches: 'all' for all todos, 'pending' for uncompleted, 'completed' for completed todos"
            }
          },
          "required" => ["query"]
        }
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
      "search_content" ->
        %{
          action: :search_content,
          query: tool_use.input["query"],
          content_type: tool_use.input["content_type"] || "all",
          limit: tool_use.input["limit"] || 10,
          date_from: tool_use.input["date_from"],
          date_to: tool_use.input["date_to"],
          todo_status: tool_use.input["todo_status"] || "all"
        }
        
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
    result = retry_with_backoff(fn ->
      AnthropicClient.send_message(updated_messages, system_prompt, tools)
    end, max_retries: 2, retry_on: :timeout)
    
    case result do
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
    
    result = retry_with_backoff(fn ->
      AnthropicClient.send_message(updated_messages, system_prompt, tools)
    end, max_retries: 2, retry_on: :timeout)
    
    case result do
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

  defp execute_journal_search(query, opts) do
    case EmbeddingsService.search_journal_entries(query, opts) do
      {:ok, results} ->
        formatted_results = format_journal_search_results(results)
        {:ok, formatted_results}
      
      {:error, :no_api_key} ->
        {:error, "Vector search is not available. OpenAI API key is not configured."}
      
      {:error, error} ->
        {:error, "Search failed: #{inspect(error)}"}
    end
  end

  defp execute_todo_search(query, opts) do
    # Apply todo status filtering to the search results
    case EmbeddingsService.search_todos(query, opts) do
      {:ok, results} ->
        filtered_results = apply_todo_status_filter(results, Keyword.get(opts, :todo_status, "all"))
        formatted_results = format_todo_search_results(filtered_results)
        {:ok, formatted_results}
      
      {:error, :no_api_key} ->
        {:error, "Vector search is not available. OpenAI API key is not configured."}
      
      {:error, error} ->
        {:error, "Search failed: #{inspect(error)}"}
    end
  end

  defp execute_combined_search(query, opts) do
    case EmbeddingsService.search_all(query, opts) do
      {:ok, results} ->
        # Apply todo status filtering to just the todo results
        filtered_results = results
        |> Enum.map(fn
          {:todo, todo, _score} = result ->
            todo_status = Keyword.get(opts, :todo_status, "all")
            if should_include_todo_by_status(todo, todo_status) do
              result
            else
              nil
            end
          result ->
            result
        end)
        |> Enum.reject(&is_nil/1)
        
        formatted_results = format_combined_search_results(filtered_results)
        {:ok, formatted_results}
      
      {:error, :no_api_key} ->
        {:error, "Vector search is not available. OpenAI API key is not configured."}
      
      {:error, error} ->
        {:error, "Search failed: #{inspect(error)}"}
    end
  end

  defp apply_todo_status_filter(results, "all"), do: results
  defp apply_todo_status_filter(results, status) do
    Enum.filter(results, fn {todo, _score} ->
      should_include_todo_by_status(todo, status)
    end)
  end

  defp should_include_todo_by_status(todo, "completed"), do: todo.completed
  defp should_include_todo_by_status(todo, "pending"), do: not todo.completed
  defp should_include_todo_by_status(_todo, "all"), do: true

  defp format_journal_search_results(results) do
    if Enum.empty?(results) do
      "No journal entries found matching your search query."
    else
      formatted = Enum.map_join(results, "\n\n", fn {entry, score} ->
        date = Calendar.strftime(entry.entry_date || entry.inserted_at, "%B %d, %Y")
        similarity = Float.round(score * 100, 1)
        
        """
        [Journal Entry - #{date}] (#{similarity}% match)
        #{String.slice(entry.content, 0, 300)}#{if String.length(entry.content) > 300, do: "...", else: ""}
        """
      end)
      
      "Found #{length(results)} journal entries:\n\n#{formatted}"
    end
  end

  defp format_todo_search_results(results) do
    if Enum.empty?(results) do
      "No todos found matching your search query."
    else
      formatted = Enum.map_join(results, "\n\n", fn {todo, score} ->
        similarity = Float.round(score * 100, 1)
        status = if todo.completed, do: "✓ COMPLETED", else: "○ PENDING"
        priority = String.upcase(todo.priority || "medium")
        
        due_info = case {todo.due_date, todo.due_time} do
          {nil, _} -> ""
          {date, nil} -> " | Due: #{date}"
          {date, time} -> " | Due: #{date} at #{time}"
        end
        
        tags_info = case todo.tags do
          nil -> ""
          [] -> ""
          tags -> " | Tags: " <> Enum.join(tags, ", ")
        end
        
        description = if todo.description && String.trim(todo.description) != "" do
          "\nDescription: #{String.slice(todo.description, 0, 200)}#{if String.length(todo.description) > 200, do: "...", else: ""}"
        else
          ""
        end
        
        """
        [Todo ##{todo.id} - #{status}] (#{similarity}% match)
        Title: #{todo.title} | Priority: #{priority}#{due_info}#{tags_info}#{description}
        """
      end)
      
      "Found #{length(results)} todos:\n\n#{formatted}"
    end
  end

  defp format_combined_search_results(results) do
    if Enum.empty?(results) do
      "No content found matching your search query."
    else
      formatted = Enum.map_join(results, "\n\n", fn
        {:journal_entry, entry, score} ->
          date = Calendar.strftime(entry.entry_date || entry.inserted_at, "%B %d, %Y")
          similarity = Float.round(score * 100, 1)
          
          """
          📝 [Journal Entry - #{date}] (#{similarity}% match)
          #{String.slice(entry.content, 0, 250)}#{if String.length(entry.content) > 250, do: "...", else: ""}
          """
          
        {:todo, todo, score} ->
          similarity = Float.round(score * 100, 1)
          status = if todo.completed, do: "✓", else: "○"
          priority = String.upcase(todo.priority || "medium")
          
          """
          ✅ [Todo ##{todo.id} - #{status} #{priority}] (#{similarity}% match)
          #{todo.title}#{if todo.description && String.trim(todo.description) != "", do: " - " <> String.slice(todo.description, 0, 150) <> (if String.length(todo.description || "") > 150, do: "...", else: ""), else: ""}
          """
      end)
      
      "Found #{length(results)} items:\n\n#{formatted}"
    end
  end
end