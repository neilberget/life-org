defmodule LifeOrg.AnthropicClient do
  alias LifeOrg.ApiLog
  
  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-0"
  
  def send_message(messages, system_prompt \\ nil, tools \\ []) do
    IO.puts("Getting API key...")
    api_key = get_api_key()
    IO.puts("API key length: #{String.length(api_key)}")
    
    body = build_request_body(messages, system_prompt, tools)
    IO.puts("Request body: #{inspect(body)}")
    
    headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]
    
    IO.puts("Making request to #{@api_url}...")
    start_time = System.monotonic_time(:millisecond)
    
    result = case Req.post(@api_url, json: body, headers: headers, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: response_body}} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        IO.puts("Success response received")
        
        # Log successful request
        log_api_call(:success, body, response_body, nil, duration_ms)
        
        {:ok, response_body}
      {:ok, %{status: status, body: error_body}} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        error_msg = "API error: #{status} - #{inspect(error_body)}"
        IO.puts("Error response: #{status} - #{inspect(error_body)}")
        
        # Log error response
        log_api_call(:error, body, error_body, error_msg, duration_ms)
        
        {:error, error_msg}
      {:error, error} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        error_msg = "Network error: #{inspect(error)}"
        IO.puts("Network error: #{inspect(error)}")
        
        # Log network error
        log_api_call(:error, body, nil, error_msg, duration_ms)
        
        {:error, error_msg}
    end
    
    result
  end
  
  defp build_request_body(messages, system_prompt, tools) do
    base = %{
      "model" => @model,
      "messages" => format_messages(messages),
      "max_tokens" => 8192
    }
    
    base = if system_prompt do
      Map.put(base, "system", system_prompt)
    else
      base
    end
    
    if tools != [] do
      Map.put(base, "tools", tools)
    else
      base
    end
  end
  
  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        "role" => to_string(msg.role),
        "content" => msg.content
      }
    end)
  end
  
  defp get_api_key do
    System.get_env("ANTHROPIC_API_KEY") || 
      Application.get_env(:life_org, :anthropic_api_key) ||
      raise "ANTHROPIC_API_KEY not set"
  end
  
  def extract_content_from_response(response) do
    # Extract all content blocks including text and tool_use blocks
    response["content"] || []
  end
  
  def extract_text_from_content(content_blocks) do
    # Extract only text content from response blocks
    content_blocks
    |> Enum.filter(fn block -> block["type"] == "text" end)
    |> Enum.map(fn block -> block["text"] end)
    |> Enum.join("\n")
  end
  
  def extract_tool_uses_from_content(content_blocks) do
    # Extract tool_use blocks from response
    content_blocks
    |> Enum.filter(fn block -> block["type"] == "tool_use" end)
    |> Enum.map(fn block ->
      %{
        id: block["id"],
        name: block["name"],
        input: block["input"]
      }
    end)
  end
  
  def build_tool_result_message(tool_id, result) do
    # Build a tool_result message for continuing the conversation
    %{
      "role" => "user",
      "content" => [
        %{
          "type" => "tool_result",
          "tool_use_id" => tool_id,
          "content" => result
        }
      ]
    }
  end
  
  defp log_api_call(status, request_data, response_data, error_message, duration_ms) do
    # Extract token usage from response if available
    usage = if response_data && Map.has_key?(response_data, "usage") do
      response_data["usage"]
    else
      %{}
    end
    
    input_tokens = Map.get(usage, "input_tokens")
    output_tokens = Map.get(usage, "output_tokens")
    total_tokens = if input_tokens && output_tokens, do: input_tokens + output_tokens, else: nil
    
    log_attrs = %{
      service: "anthropic",
      model: @model,
      request_data: request_data,
      response_data: response_data,
      error_message: error_message,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens,
      duration_ms: duration_ms
    }
    
    case status do
      :success -> ApiLog.log_success(log_attrs)
      :error -> ApiLog.log_error(log_attrs)
    end
    
    # Don't let logging errors crash the main request
    :ok
  rescue
    error ->
      IO.puts("Failed to log API call: #{inspect(error)}")
      :ok
  end
end