defmodule LifeOrg.AIHandler do
  import Ecto.Query
  alias LifeOrg.{AnthropicClient, EmbeddingsService, Repo, Todo, TodoComment, WorkspaceService}

  def process_message(message, journal_entries, todos, conversation_history \\ [], workspace_id) do
    system_prompt = build_system_prompt(journal_entries, todos)
    
    # Define available tools
    tools = build_tools_definition(todos)
    
    # Combine conversation history with new message
    messages = conversation_history ++ [%{role: "user", content: message}]
    
    result = retry_with_backoff(fn ->
      AnthropicClient.send_message(messages, system_prompt, tools)
    end, max_retries: 2, retry_on: :timeout)
    
    case result do
      {:ok, response} ->
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
        {:error, "Sorry, I encountered an error: #{error}"}
    end
  end

  def extract_todos_from_journal(journal_content, existing_todos \\ [], journal_entry_id \\ nil, workspace_id \\ nil, return_conversation \\ true) do
    # Get existing tags for context
    existing_tags = get_unique_tags(existing_todos)
    tags_context = case existing_tags do
      [] -> "No existing tags."
      tags -> "Existing tags: " <> Enum.join(tags, ", ")
    end
    
    # Get existing projects for context
    existing_projects = get_unique_projects(existing_todos)
    projects_context = case existing_projects do
      [] -> "No existing projects."
      projects -> "Existing projects: " <> Enum.join(Enum.take(Enum.map(projects, & &1.name), 15), ", ") <> if length(projects) > 15, do: "...", else: ""
    end
    
    # Provide basic statistics about existing todos rather than full details
    total_todos = length(existing_todos)
    completed_todos = Enum.count(existing_todos, & &1.completed)
    pending_todos = total_todos - completed_todos
    
    # Show only high-priority and current todos to reduce context
    priority_todos = Enum.filter(existing_todos, &(&1.priority == "high" and not &1.completed))
    current_todos = Enum.filter(existing_todos, &(&1.current and not &1.completed))
    important_todos = (priority_todos ++ current_todos) |> Enum.uniq_by(& &1.id)
    
    important_todos_context = case important_todos do
      [] -> "No high-priority or current todos."
      todos ->
        "High-priority and current todos:\n" <>
        (todos
        |> Enum.map(fn todo ->
          tags_info = case todo.tags do
            nil -> ""
            [] -> ""
            tags -> " [Tags: " <> Enum.join(tags, ", ") <> "]"
          end
          current_marker = if todo.current, do: " [CURRENT]", else: ""
          "ID: #{todo.id} | #{todo.title} (#{todo.priority})#{tags_info}#{current_marker}" <>
          if todo.description && String.trim(todo.description) != "", do: " - #{todo.description}", else: ""
        end)
        |> Enum.join("\n"))
    end

    system_prompt = """
    You are an assistant that extracts simple, high-level actionable todos from journal entries.

    WORKSPACE OVERVIEW:
    - Total todos: #{pending_todos} pending, #{completed_todos} completed
    - #{tags_context}
    - #{projects_context}
    
    #{important_todos_context}

    EXTRACTION GUIDELINES:
    
    1. KEEP TODOS SIMPLE: Create concise, high-level todos that capture the main action without detailed implementation steps.
    
    2. FOCUS ON ACTIONABLE ITEMS: Only create todos for clear, actionable tasks mentioned in the journal entry.
    
    3. AVOID OVER-ENGINEERING: Don't break down tasks into detailed sub-steps or create comprehensive implementation plans. Keep descriptions brief and to-the-point.
    
    4. USE SEARCH SPARINGLY: Only search for context if you need to avoid duplicating an existing todo or understand if something is already completed.

    For each todo you create:
    - Use a clear, concise title (the main action)
    - Keep descriptions brief and high-level
    - Set appropriate priority and tags based on the journal content
    - ASSIGN APPROPRIATE PROJECTS: When the journal mentions specific projects, systems, or work areas, match them to existing projects or create new ones. For example, if the journal mentions "mobile app", "website", "API", "client work", etc., assign appropriate project names.
    - Use existing projects when possible, but create new project names when the work doesn't fit existing categories
    - Avoid detailed step-by-step instructions or comprehensive task breakdowns
    
    PROJECT MATCHING EXAMPLES:
    - Journal mentions "fix the mobile app bug" → assign to "Mobile App" project
    - Journal mentions "update the website design" → assign to "Website" or "Web App" project  
    - Journal mentions "client meeting about XYZ" → assign to "XYZ Client" project
    - Journal mentions "API documentation" → assign to "API Development" project
    
    Example: Instead of "Review implementation, design function, add types, test with games, document usage" just create "Add auto-refresh function to heygg-common" and assign to "HeyGG Common" project
    """
    
    # Define tools for journal todo extraction
    tools = build_tools_definition(existing_todos)
    
    messages = [%{role: "user", content: journal_content}]
    
    # Use the enhanced tool processing pipeline that can handle multiple rounds of tools
    result = retry_with_backoff(fn ->
      AnthropicClient.send_message(messages, system_prompt, tools)
    end, max_retries: 2, retry_on: :timeout)
    
    case result do
      {:ok, response} ->
        content_blocks = AnthropicClient.extract_content_from_response(response)
        tool_uses = AnthropicClient.extract_tool_uses_from_content(content_blocks)
        
        # If there are tool uses, we need to process them and continue the conversation
        if length(tool_uses) > 0 do
          execute_tools_and_extract_final_actions(messages, system_prompt, tools, content_blocks, tool_uses, workspace_id, existing_todos, journal_entry_id, return_conversation)
        else
          # No tools used, just return empty actions
          if return_conversation do
            assistant_message = AnthropicClient.extract_text_from_content(content_blocks)
            conversation_messages = [
              %{role: "system", content: system_prompt},
              %{role: "user", content: journal_content},
              %{role: "assistant", content: assistant_message}
            ]
            {:ok, [], conversation_messages}
          else
            {:ok, []}
          end
        end
        
      {:error, _error} ->
        if return_conversation do
          {:ok, [], []}
        else
          {:ok, []}
        end
    end
  end

  # Handle multi-round tool processing for journal todo extraction
  defp execute_tools_and_extract_final_actions(messages, system_prompt, tools, content_blocks, tool_uses, workspace_id, existing_todos, journal_entry_id, return_conversation) do
    # Execute all tools and get their results
    tool_results = Enum.map(tool_uses, fn tool_use ->
      case execute_tool_action(%{
        action: case tool_use.name do
          "search_content" -> :search_content
          "create_todo" -> :create_todo
          "update_todo" -> :update_todo
          "complete_todo" -> :complete_todo
          "delete_todo" -> :delete_todo
          "get_todo_by_id" -> :get_todo_by_id
          "add_todo_comment" -> :add_todo_comment
          _ -> :unknown
        end
      } |> Map.merge(convert_tool_params(tool_use)), workspace_id) do
        {:ok, result} -> 
          %{
            "type" => "tool_result",
            "tool_use_id" => tool_use.id,
            "content" => format_tool_result({:ok, result}, tool_use.name)
          }
        {:error, error} ->
          %{
            "type" => "tool_result", 
            "tool_use_id" => tool_use.id,
            "content" => "Error: #{error}",
            "is_error" => true
          }
      end
    end)

    # Continue the conversation with tool results
    messages_with_assistant = messages ++ [%{role: "assistant", content: content_blocks}]
    messages_with_tools = messages_with_assistant ++ [%{role: "user", content: tool_results}]

    # Get the next response from AI
    case retry_with_backoff(fn ->
      AnthropicClient.send_message(messages_with_tools, system_prompt, tools)
    end, max_retries: 2, retry_on: :timeout) do
      {:ok, response} ->
        content_blocks = AnthropicClient.extract_content_from_response(response)
        tool_uses = AnthropicClient.extract_tool_uses_from_content(content_blocks)
        
        if length(tool_uses) > 0 do
          # More tools to execute - recurse
          execute_tools_and_extract_final_actions(messages_with_tools, system_prompt, tools, content_blocks, tool_uses, workspace_id, existing_todos, journal_entry_id, return_conversation)
        else
          # No more tools - extract final actions and optionally return conversation
          {:ok, actions} = extract_todo_actions_from_results(tool_results, existing_todos, journal_entry_id)
          if return_conversation do
            final_assistant_message = AnthropicClient.extract_text_from_content(content_blocks)
            conversation_messages = [
              %{role: "system", content: system_prompt}
            ] ++ messages_with_tools ++ [
              %{role: "assistant", content: final_assistant_message}
            ]
            {:ok, actions, conversation_messages}
          else
            {:ok, actions}
          end
        end
        
      {:error, _error} ->
        # Fall back to extracting actions from current tool results
        {:ok, actions} = extract_todo_actions_from_results(tool_results, existing_todos, journal_entry_id)
        if return_conversation do
          conversation_messages = [
            %{role: "system", content: system_prompt}
          ] ++ messages_with_tools
          {:ok, actions, conversation_messages}
        else
          {:ok, actions}
        end
    end
  end

  defp convert_tool_params(tool_use) do
    case tool_use.name do
      "search_content" ->
        %{
          query: tool_use.input["query"],
          content_type: tool_use.input["content_type"] || "all",
          limit: tool_use.input["limit"] || 10,
          date_from: tool_use.input["date_from"],
          date_to: tool_use.input["date_to"],
          todo_status: tool_use.input["todo_status"] || "all"
        }
      "create_todo" ->
        %{
          title: tool_use.input["title"],
          description: tool_use.input["description"] || "",
          priority: tool_use.input["priority"] || "medium",
          tags: tool_use.input["tags"] || [],
          projects: tool_use.input["projects"] || []
        }
      "update_todo" ->
        updates = %{}
        |> maybe_add("title", tool_use.input["title"])
        |> maybe_add("description", tool_use.input["description"])
        |> maybe_add("priority", tool_use.input["priority"])
        |> maybe_add("tags", tool_use.input["tags"])
        |> maybe_add("projects", tool_use.input["projects"])
        
        %{id: tool_use.input["id"], updates: updates}
      "complete_todo" ->
        %{id: tool_use.input["id"]}
      "delete_todo" ->
        %{id: tool_use.input["id"]}
      "get_todo_by_id" ->
        %{id_or_url: tool_use.input["id_or_url"]}
      "add_todo_comment" ->
        %{id: tool_use.input["id"], content: tool_use.input["content"]}
      _ ->
        %{}
    end
  end

  defp format_tool_result(result, tool_name) do
    case tool_name do
      "search_content" ->
        case result do
          {:ok, formatted_string} when is_binary(formatted_string) ->
            formatted_string
          {:ok, []} ->
            "No relevant content found."
          {:ok, results} when is_list(results) ->
            formatted_results = Enum.map(results, fn 
              {:journal_entry, entry, score} ->
                date = Calendar.strftime(entry.entry_date || entry.inserted_at, "%B %d, %Y")
                "Journal Entry (#{date}, similarity: #{Float.round(score, 3)}): #{String.slice(entry.content, 0, 200)}#{if String.length(entry.content) > 200, do: "...", else: ""}"
              {:todo, todo, score} ->
                status = if todo.completed, do: "COMPLETED", else: "PENDING"
                "Todo (#{status}, similarity: #{Float.round(score, 3)}): #{todo.title}#{if todo.description && String.trim(todo.description) != "", do: " - #{todo.description}", else: ""}"
            end)
            "Found #{length(results)} relevant items:\n" <> Enum.join(formatted_results, "\n")
          error ->
            "Search failed: #{inspect(error)}"
        end
      "create_todo" ->
        case result do
          {:ok, %Todo{} = todo} -> "Successfully created todo: #{todo.title} (ID: #{todo.id})"
          {:ok, todo} -> "Created todo: #{inspect(todo)}"
          {:error, %Ecto.Changeset{} = changeset} -> 
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
              Enum.reduce(opts, msg, fn {key, value}, acc ->
                String.replace(acc, "%{#{key}}", to_string(value))
              end)
            end)
            "Failed to create todo: #{inspect(errors)}"
          {:error, error} -> "Failed to create todo: #{inspect(error)}"
          error -> "Unexpected result: #{inspect(error)}"
        end
      "update_todo" ->
        case result do
          {:ok, %Todo{} = todo} -> "Successfully updated todo: #{todo.title} (ID: #{todo.id})"
          {:ok, todo} -> "Updated todo: #{inspect(todo)}"
          {:error, %Ecto.Changeset{} = changeset} -> 
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
              Enum.reduce(opts, msg, fn {key, value}, acc ->
                String.replace(acc, "%{#{key}}", to_string(value))
              end)
            end)
            "Failed to update todo: #{inspect(errors)}"
          {:error, error} -> "Failed to update todo: #{inspect(error)}"
          error -> "Unexpected result: #{inspect(error)}"
        end
      "complete_todo" ->
        case result do
          {:ok, %Todo{} = todo} -> "Successfully completed todo: #{todo.title} (ID: #{todo.id})"
          {:ok, todo} -> "Completed todo: #{inspect(todo)}"
          {:error, error} -> "Failed to complete todo: #{inspect(error)}"
          error -> "Unexpected result: #{inspect(error)}"
        end
      "add_todo_comment" ->
        case result do
          {:ok, message} when is_binary(message) -> message
          {:ok, _result} -> "Comment added successfully"
          {:error, error} -> "Failed to add comment: #{inspect(error)}"
          error -> "Unexpected result: #{inspect(error)}"
        end
      _ ->
        inspect(result)
    end
  end

  defp extract_todo_actions_from_results(_tool_results, _existing_todos, _journal_entry_id) do
    # For the journal extraction pipeline, we need to return empty actions since
    # the AI has already executed the tools directly. The UI will be updated
    # through other mechanisms.
    # TODO: In the future, we might want to track which todos were created/updated
    # during this process for better UI feedback
    {:ok, []}
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
        Process.sleep(delay)
        do_retry(fun, attempt + 1, max_retries, retry_on)
        
      {:error, "Network error: " <> rest} = error when attempt < max_retries ->
        # Also handle string-formatted network errors that might contain timeout info
        if String.contains?(rest, "timeout") and retry_on == :timeout do
          delay = round(:timer.seconds(2) * :math.pow(2, attempt))
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
    
    # Get existing projects for context
    existing_projects = get_unique_projects(todos)
    projects_context = case existing_projects do
      [] -> "No existing projects."
      projects -> "Available projects: " <> Enum.join(Enum.take(Enum.map(projects, & &1.name), 15), ", ") <> if length(projects) > 15, do: "...", else: ""
    end
    
    """
    You are a helpful life organization assistant. You can help users manage their tasks and reflect on their life using available tools.
    
    CONTENT OVERVIEW:
    - Journal: #{journal_summary}
    - Todos: #{todos_summary}
    - #{tags_context}
    - #{projects_context}
    
    HIGH PRIORITY & CURRENT ITEMS:
    #{priority_context}
    
    IMPORTANT: Use the search_content tool to find relevant journal entries or todos when you need specific context or past information. Don't guess about past content - search for it instead.
    
    You have access to tools for managing todos, semantic content search, and web search capabilities. Use these tools when:
    - The user asks you to create, update, complete, or delete tasks
    - You need to find relevant journal entries or todos based on semantic similarity (use search_content tool)
    - You need current information from the internet to provide helpful advice or context
    - The user asks questions that require up-to-date information beyond your knowledge cutoff
    - The user wants to find past entries or todos related to a specific topic or theme
    
    When creating todos, please suggest appropriate tags and projects based on:
    - Existing tags and projects that are relevant to the new task
    - Common categorizations like "work", "personal", "urgent", "project", "store", "health", etc.
    - Context from the user's message or journal entries
    
    PROJECT ASSIGNMENT GUIDELINES:
    - Always assign todos to appropriate projects when the context suggests specific work areas, systems, or initiatives
    - Use existing projects when the task clearly fits an existing project category
    - Create new projects with descriptive names when tasks don't fit existing projects
    - Examples: "Mobile App", "Website Redesign", "Client X", "API Development", "Marketing Campaign", etc.
    
    Use existing tags and projects when possible to maintain consistency, but feel free to suggest new ones when appropriate.
    
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
            },
            "projects" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Project names to organize this todo. Will create projects if they don't exist. Use descriptive names like 'Web App', 'Mobile App', 'API Development', etc."
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
            },
            "projects" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "New project names for the todo. Will create projects if they don't exist."
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
      },
      %{
        "name" => "add_todo_comment",
        "description" => "Add a comment to a specific todo item with status updates, notes, or other contextual information",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{
              "type" => "integer",
              "description" => "The ID of the todo to add a comment to"
            },
            "content" => %{
              "type" => "string",
              "description" => "The comment content (supports markdown)"
            }
          },
          "required" => ["id", "content"]
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
          projects: tool_use.input["projects"] || [],
          journal_entry_id: journal_entry_id
        }
        
      "update_todo" ->
        updates = %{}
        |> maybe_add("title", tool_use.input["title"])
        |> maybe_add("description", tool_use.input["description"])
        |> maybe_add("priority", tool_use.input["priority"])
        |> maybe_add("tags", tool_use.input["tags"])
        |> maybe_add("projects", tool_use.input["projects"])
        
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
        
      "add_todo_comment" ->
        %{
          action: :add_todo_comment,
          id: tool_use.input["id"],
          content: tool_use.input["content"]
        }
    end
  end
  
  defp maybe_add(map, _key, value) when value == "" or is_nil(value), do: map
  defp maybe_add(map, "tags", value) when is_list(value) do
    # Ensure all tags are strings
    tags = Enum.map(value, &to_string/1)
    Map.put(map, "tags", tags)
  end
  defp maybe_add(map, "tags", value) when not is_nil(value) do
    # Convert single tag to list
    Map.put(map, "tags", [to_string(value)])
  end
  defp maybe_add(map, "projects", value) when is_list(value) do
    # Ensure all projects are strings
    projects = Enum.map(value, &to_string/1)
    Map.put(map, "projects", projects)
  end
  defp maybe_add(map, "projects", value) when not is_nil(value) do
    # Convert single project to list
    Map.put(map, "projects", [to_string(value)])
  end
  defp maybe_add(map, key, value) when is_list(value) and value != [], do: Map.put(map, key, value)
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
  
  defp get_unique_tags(todos) do
    todos
    |> Enum.flat_map(fn todo -> todo.tags || [] end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp get_unique_projects(todos) do
    todos
    |> Enum.flat_map(fn todo -> todo.projects || [] end)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
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
    # Ensure tags is always a list of strings
    tags = case params.tags do
      nil -> []
      [] -> []
      tags when is_list(tags) -> Enum.map(tags, &to_string/1)
      tags -> [to_string(tags)]
    end
    
    # Ensure projects is always a list of strings
    projects = case params[:projects] do
      nil -> []
      [] -> []
      projects when is_list(projects) -> Enum.map(projects, &to_string/1)
      projects -> [to_string(projects)]
    end
    
    todo_attrs = %{
      "title" => params.title,
      "description" => params.description,
      "priority" => params.priority,
      "tags" => tags,
      "projects" => projects,
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

  def execute_tool_action(%{action: :add_todo_comment, id: id, content: content}, workspace_id) do
    case Repo.get(Todo, id) do
      nil -> 
        {:error, "Todo not found with ID: #{id}"}
      todo ->
        # Verify todo belongs to workspace
        if todo.workspace_id == workspace_id do
          case Repo.insert(
                 TodoComment.changeset(
                   %TodoComment{},
                   %{"todo_id" => id, "content" => content}
                 )
               ) do
            {:ok, _comment} -> 
              {:ok, "Comment added successfully: #{String.slice(content, 0, 100)}#{if String.length(content) > 100, do: "...", else: ""}"}
            {:error, error} -> 
              {:error, "Failed to add comment: #{inspect(error)}"}
          end
        else
          {:error, "Todo not found in current workspace"}
        end
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
    system_prompt = build_todo_system_prompt(todo, todo_comments, all_todos, journal_entries)
    
    # Define available tools for todo conversations
    tools = build_todo_tools_definition(todo, all_todos)
    
    # Combine conversation history with new message
    messages = conversation_history ++ [%{role: "user", content: message}]
    
    result = retry_with_backoff(fn ->
      AnthropicClient.send_message(messages, system_prompt, tools)
    end, max_retries: 2, retry_on: :timeout)
    
    case result do
      {:ok, response} ->
        content_blocks = AnthropicClient.extract_content_from_response(response)
        # Extract text message and tool uses separately
        assistant_message = AnthropicClient.extract_text_from_content(content_blocks)
        
        tool_uses = AnthropicClient.extract_tool_uses_from_content(content_blocks)
        
        # If there are tool uses, execute them and get final response
        if length(tool_uses) > 0 do
          try do
            execute_todo_tools_and_continue(messages, system_prompt, tools, content_blocks, tool_uses, workspace_id, todo, all_todos)
          rescue
            error ->
              {:error, "Tool execution failed: #{inspect(error)}"}
          end
        else
          # No tools used, return the response directly
          {:ok, assistant_message, []}
        end
        
      {:error, error} ->
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
    
    # Add detailed project context when todo has associated projects
    project_context = format_project_context(todo)
    
    """
    You are a helpful personal assistant focused on helping with a specific todo item. You understand the user's broader life context but specialize in providing targeted advice, suggestions, and task management for the current todo.

    CURRENT TODO:
    #{todo_details}

    TODO COMMENTS & DISCUSSION:
    #{comments_context}

    LIFE CONTEXT:
    #{entries_context}

    #{project_context}

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
    
    # Include project information if available
    projects_info = case todo.projects do
      nil -> ""
      [] -> ""
      projects -> " | Projects: " <> Enum.join(Enum.map(projects, & &1.name), ", ")
    end
    
    description = if todo.description && String.trim(todo.description) != "" do
      "\nDescription: #{todo.description}"
    else
      ""
    end
    
    """
    ID: #{todo.id} | #{status} | Priority: #{priority} | Title: #{todo.title}#{due_info}#{tags_info}#{projects_info}#{description}
    """
  end

  defp format_project_context(todo) do
    case todo.projects do
      nil -> ""
      [] -> ""
      projects ->
        project_details = Enum.map(projects, fn project ->
          description_part = if project.description && String.trim(project.description) != "" do
            "\n    Description: #{project.description}"
          else
            ""
          end
          
          url_part = if project.url && String.trim(project.url) != "" do
            "\n    URL: #{project.url}"
          else
            ""
          end
          
          "  - #{project.name}#{description_part}#{url_part}"
        end)
        
        """
PROJECT CONTEXT:
This todo is associated with the following project(s):
#{Enum.join(project_details, "\n")}

Use this project information to provide more targeted advice and suggestions that align with the project's goals and context.
"""
    end
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
            },
            "projects" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "Project names to organize this todo. Will create projects if they don't exist."
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
            "projects" => %{
              "type" => "array",
              "items" => %{"type" => "string"},
              "description" => "New project names for the todo. Will create projects if they don't exist."
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
          tags: tool_use.input["tags"] || [],
          projects: tool_use.input["projects"] || []
        }
        
      "update_current_todo" ->
        updates = %{}
        |> maybe_add("title", tool_use.input["title"])
        |> maybe_add("description", tool_use.input["description"])
        |> maybe_add("priority", tool_use.input["priority"])
        |> maybe_add("tags", tool_use.input["tags"])
        |> maybe_add("projects", tool_use.input["projects"])
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
    # Extract the original text content from the response (if any)
    original_text = AnthropicClient.extract_text_from_content(content_blocks)
    
    # Execute each tool and collect results
    tool_results = Enum.map(tool_uses, fn tool_use ->
      # Convert to action and execute
      action = convert_tool_use_to_action(tool_use, [], nil)
      result = execute_tool_action(action, workspace_id)
      
      # Format the tool result properly using the existing format_tool_result function
      formatted_result = format_tool_result(result, tool_use.name)
      
      # Build tool result message
      AnthropicClient.build_tool_result_message(tool_use.id, formatted_result)
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
          execute_tools_and_continue(updated_messages, system_prompt, tools, final_content_blocks, final_tool_uses, workspace_id)
        else
          # No more tools, extract final message
          final_message = AnthropicClient.extract_text_from_content(final_content_blocks)
          
          # Convert tool actions for UI updates (no tool IDs needed for this)
          tool_actions = Enum.map(tool_uses, &convert_tool_use_to_action(&1, []))
          
          # If there was original text content with the tools, preserve it
          # If the final response is empty or just acknowledgment, use the original text
          combined_message = case {String.trim(original_text), String.trim(final_message)} do
            {"", final} when final != "" -> 
              # No original text, use final response
              final
            {original, ""} ->
              # Original text exists, no final response - use original
              original
            {original, final} when original != "" and final != "" ->
              # Both exist - combine them appropriately
              if String.length(final) < 50 and (String.contains?(final, "successfully") or String.contains?(final, "updated") or String.contains?(final, "completed")) do
                # Final message looks like a brief acknowledgment, use original
                original
              else
                # Both are substantial, combine them
                original <> "\n\n" <> final
              end
            _ ->
              # Fallback to final message
              final_message
          end
          
          {:ok, combined_message, tool_actions}
        end
        
      {:error, error} ->
        {:error, "Sorry, I encountered an error processing the tool results: #{error}"}
    end
  end

  defp execute_todo_tools_and_continue(messages, system_prompt, tools, content_blocks, tool_uses, workspace_id, todo, all_todos) do
    # Extract the original text content from the response (if any)
    original_text = AnthropicClient.extract_text_from_content(content_blocks)
    
    # Execute each tool and collect results
    tool_results = Enum.map(tool_uses, fn tool_use ->
      # Convert to action and execute
      action = convert_todo_tool_use_to_action(tool_use, todo, all_todos)
      
      result = execute_tool_action(action, workspace_id)
      
      # Format the tool result properly using the existing format_tool_result function
      formatted_result = format_tool_result(result, tool_use.name)
      
      # Build tool result message
      AnthropicClient.build_tool_result_message(tool_use.id, formatted_result)
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
          
          # If there was original text content with the tools, preserve it
          # If the final response is empty or just acknowledgment, use the original text
          combined_message = case {String.trim(original_text), String.trim(final_message)} do
            {"", final} when final != "" -> 
              # No original text, use final response
              final
            {original, ""} ->
              # Original text exists, no final response - use original
              original
            {original, final} when original != "" and final != "" ->
              # Both exist - combine them appropriately
              if String.length(final) < 50 and (String.contains?(final, "successfully") or String.contains?(final, "updated") or String.contains?(final, "completed")) do
                # Final message looks like a brief acknowledgment, use original
                original
              else
                # Both are substantial, combine them
                original <> "\n\n" <> final
              end
            _ ->
              # Fallback to final message
              final_message
          end
          
          {:ok, combined_message, tool_actions}
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

  def process_journal_message(message, journal_entry, related_todos, all_todos, journal_entries, conversation_history \\ [], workspace_id) do
    system_prompt = build_journal_system_prompt(journal_entry, related_todos, all_todos, journal_entries)
    
    # Define available tools for journal conversations
    tools = build_journal_tools_definition(journal_entry, all_todos, workspace_id)
    
    # Combine conversation history with new message
    messages = conversation_history ++ [%{role: "user", content: message}]
    
    result = retry_with_backoff(fn ->
      AnthropicClient.send_message(messages, system_prompt, tools)
    end, max_retries: 2, retry_on: :timeout)
    
    case result do
      {:ok, response} ->
        content_blocks = AnthropicClient.extract_content_from_response(response)
        # Extract text message and tool uses separately
        assistant_message = AnthropicClient.extract_text_from_content(content_blocks)
        
        tool_uses = AnthropicClient.extract_tool_uses_from_content(content_blocks)
        
        # If there are tool uses, execute them and get final response
        if length(tool_uses) > 0 do
          try do
            execute_journal_tools_and_continue(messages, system_prompt, tools, content_blocks, tool_uses, workspace_id, journal_entry, all_todos)
          rescue
            error ->
              {:error, "Tool execution failed: #{inspect(error)}"}
          end
        else
          # No tools used, return the response directly
          {:ok, assistant_message, []}
        end
        
      {:error, error} ->
        {:error, "Sorry, I encountered an error: #{error}"}
    end
  end

  defp build_journal_system_prompt(journal_entry, related_todos, _all_todos, journal_entries) do
    # Format the current journal entry details
    journal_details = format_journal_entry_details(journal_entry)
    
    # Format related todos (todos created from this journal entry)
    related_todos_context = format_related_todos(related_todos)
    
    # Recent entries context (limited to avoid token bloat)
    recent_entries_context = format_recent_journal_entries(journal_entries, journal_entry.id)
    
    """
    You are an AI assistant helping a user with their journal entry and personal productivity system.

    ## Current Journal Entry Context
    #{journal_details}

    #{related_todos_context}

    #{recent_entries_context}

    ## Available Tools
    You have access to various tools to help manage todos and search content. Use these tools when:
    - The user asks about creating, updating, or managing todos
    - You need to find related information from their journal entries or todos
    - The user wants to take action based on their journal entry

    ## Guidelines
    - Be conversational and helpful
    - Reference the journal entry content naturally in your responses
    - Suggest actionable insights when appropriate
    - Use tools to help the user manage their tasks and find related content
    - Focus on helping them reflect on their journal entry and plan next steps

    Your goal is to help the user gain insights from their journal entry and manage their personal productivity effectively.
    """
  end

  defp build_journal_tools_definition(_journal_entry, all_todos, _workspace_id) do
    # Include the same tools available for todo management (which already includes search_content)
    build_todo_tools_definition(%{id: nil}, all_todos)
  end

  defp execute_journal_tools_and_continue(messages, system_prompt, tools, content_blocks, tool_uses, workspace_id, journal_entry, all_todos) do
    # Execute each tool and collect results
    tool_results = Enum.map(tool_uses, fn tool_use ->
      # Convert to action and execute
      action = convert_journal_tool_use_to_action(tool_use, journal_entry, all_todos)
      
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
          execute_journal_tools_and_continue(updated_messages, system_prompt, tools, final_content_blocks, final_tool_uses, workspace_id, journal_entry, all_todos)
        else
          # No more tools, extract final message
          final_message = AnthropicClient.extract_text_from_content(final_content_blocks)
          
          # Convert tool actions for UI updates
          tool_actions = Enum.map(tool_uses, &convert_journal_tool_use_to_action(&1, journal_entry, all_todos))
          
          {:ok, final_message, tool_actions}
        end
        
      {:error, error} ->
        {:error, "Tool execution and response failed: #{error}"}
    end
  end

  defp convert_journal_tool_use_to_action(tool_use, journal_entry, _all_todos) do
    case tool_use.name do
      "search_content" ->
        %{
          action: :search_content,
          query: tool_use.input["query"],
          content_type: tool_use.input["content_type"] || "both",
          limit: tool_use.input["limit"] || 5
        }
        
      "create_todo" ->
        %{
          action: :create_todo,
          title: tool_use.input["title"],
          description: tool_use.input["description"] || "",
          priority: tool_use.input["priority"] || "medium",
          tags: tool_use.input["tags"] || [],
          projects: tool_use.input["projects"] || []
        }
        
      "create_related_todo" ->
        %{
          action: :create_todo,
          title: tool_use.input["title"],
          description: tool_use.input["description"] || "",
          priority: tool_use.input["priority"] || "medium",
          tags: tool_use.input["tags"] || [],
          projects: tool_use.input["projects"] || [],
          journal_entry_id: journal_entry.id
        }
        
      "update_todo" ->
        updates = %{}
        |> maybe_add("title", tool_use.input["title"])
        |> maybe_add("description", tool_use.input["description"])
        |> maybe_add("priority", tool_use.input["priority"])
        |> maybe_add("tags", tool_use.input["tags"])
        |> maybe_add("projects", tool_use.input["projects"])
        |> maybe_add("due_date", tool_use.input["due_date"])
        
        %{
          action: :update_todo,
          id: tool_use.input["id"],
          updates: updates
        }
        
      "complete_todo" ->
        %{
          action: :complete_todo,
          id: tool_use.input["id"],
          completion_note: tool_use.input["completion_note"]
        }
        
      "get_todo_by_id" ->
        %{
          action: :get_todo_by_id,
          id_or_url: tool_use.input["id_or_url"]
        }
        
      _ ->
        {:error, "Unknown tool: #{tool_use.name}"}
    end
  end

  defp format_journal_entry_details(journal_entry) do
    date = Calendar.strftime(journal_entry.entry_date || journal_entry.inserted_at, "%B %d, %Y")
    
    """
    **Journal Entry from #{date}**
    #{journal_entry.content}
    """
  end

  defp format_related_todos(related_todos) do
    if Enum.empty?(related_todos) do
      ""
    else
      todos_list = Enum.map_join(related_todos, "\n", fn todo ->
        status = if todo.completed, do: "✓", else: "○"
        priority = String.upcase(todo.priority || "medium")
        "- #{status} [#{priority}] #{todo.title}"
      end)
      
      """
      
      **Related Todos Created from This Journal Entry**
      #{todos_list}
      """
    end
  end

  defp format_recent_journal_entries(journal_entries, current_entry_id) do
    # Get recent entries (excluding the current one) limited to 3 to avoid token bloat
    recent_entries = journal_entries
    |> Enum.reject(&(&1.id == current_entry_id))
    |> Enum.take(3)
    
    if Enum.empty?(recent_entries) do
      ""
    else
      entries_list = Enum.map_join(recent_entries, "\n\n", fn entry ->
        date = Calendar.strftime(entry.entry_date || entry.inserted_at, "%B %d, %Y")
        content_preview = String.slice(entry.content, 0, 200)
        content_preview = if String.length(entry.content) > 200, do: content_preview <> "...", else: content_preview
        
        "**#{date}**: #{content_preview}"
      end)
      
      """
      
      **Recent Journal Entries for Context**
      #{entries_list}
      """
    end
  end
end