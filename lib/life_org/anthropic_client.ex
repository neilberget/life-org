defmodule LifeOrg.AnthropicClient do
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
  
  defp build_request_body(messages, system_prompt, tools) do
    base = %{
      "model" => @model,
      "messages" => format_messages(messages),
      "max_tokens" => 1024
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
end