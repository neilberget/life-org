defmodule LifeOrg.AnthropicClient do
  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-0"
  
  def send_message(messages, system_prompt \\ nil) do
    IO.puts("Getting API key...")
    api_key = get_api_key()
    IO.puts("API key length: #{String.length(api_key)}")
    
    body = build_request_body(messages, system_prompt)
    IO.puts("Request body: #{inspect(body)}")
    
    headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]
    
    IO.puts("Making request to #{@api_url}...")
    case Req.post(@api_url, json: body, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        IO.puts("Success response received")
        {:ok, body}
      {:ok, %{status: status, body: body}} ->
        IO.puts("Error response: #{status} - #{inspect(body)}")
        {:error, "API error: #{status} - #{inspect(body)}"}
      {:error, error} ->
        IO.puts("Network error: #{inspect(error)}")
        {:error, "Network error: #{inspect(error)}"}
    end
  end
  
  defp build_request_body(messages, system_prompt) do
    base = %{
      "model" => @model,
      "messages" => format_messages(messages),
      "max_tokens" => 1024
    }
    
    if system_prompt do
      Map.put(base, "system", system_prompt)
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
  
  def extract_tools_from_response(response) do
    # Parse tool use blocks from Claude's response
    # This is a simplified version - you might want to make it more robust
    content = response["content"] || []
    
    tools = Enum.flat_map(content, fn
      %{"type" => "tool_use", "name" => name, "input" => input} ->
        [%{name: name, input: input}]
      _ ->
        []
    end)
    
    {:ok, tools}
  end
end