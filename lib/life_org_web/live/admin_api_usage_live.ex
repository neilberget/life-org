defmodule LifeOrgWeb.AdminApiUsageLive do
  use LifeOrgWeb, :live_view
  alias LifeOrg.ApiLog

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "API Usage")
      |> assign(:logs, [])
      |> assign(:stats, %{})
      |> assign(:filter_service, "all")
      |> assign(:page, 1)
      |> assign(:per_page, 25)
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = String.to_integer(params["page"] || "1")
    service = params["service"] || "all"
    
    socket =
      socket
      |> assign(:page, page)
      |> assign(:filter_service, service)
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_service", %{"service" => service}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/api_usage?service=#{service}&page=1")}
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("view_log", %{"log_id" => log_id}, socket) do
    log = Enum.find(socket.assigns.logs, &(&1.id == String.to_integer(log_id)))
    {:noreply, assign(socket, :viewing_log, log)}
  end

  @impl true
  def handle_event("close_log", _, socket) do
    {:noreply, assign(socket, :viewing_log, nil)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  defp load_data(socket) do
    %{page: page, per_page: per_page, filter_service: service} = socket.assigns
    offset = (page - 1) * per_page

    logs = case service do
      "all" -> ApiLog.recent_logs(per_page, offset)
      service -> ApiLog.logs_by_service(service, per_page, offset)
    end

    stats = ApiLog.usage_stats()

    socket
    |> assign(:logs, logs)
    |> assign(:stats, stats)
  end

  defp format_duration(nil), do: "-"
  defp format_duration(%Decimal{} = ms) do
    ms
    |> Decimal.round(0)
    |> Decimal.to_integer()
    |> format_duration()
  end
  defp format_duration(ms) when is_integer(ms) do
    cond do
      ms < 1000 -> "#{ms}ms"
      ms < 60000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{Float.round(ms / 60000, 1)}m"
    end
  end

  defp format_tokens(nil), do: "-"
  defp format_tokens(%Decimal{} = tokens) do
    tokens
    |> Decimal.to_integer()
    |> format_tokens()
  end
  defp format_tokens(tokens) when is_integer(tokens) do
    tokens
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp calculate_success_rate(total_requests, success_count) do
    cond do
      is_nil(total_requests) or is_nil(success_count) -> "0"
      to_number(total_requests) == 0 -> "0"
      true -> 
        total = to_number(total_requests)
        success = to_number(success_count)
        (success / total * 100) |> Float.round(1) |> to_string()
    end
  end

  defp to_number(nil), do: 0
  defp to_number(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_number(num) when is_number(num), do: num

  defp extract_system_prompt(request_data) do
    request_data["system"]
  end

  defp extract_messages(request_data) do
    request_data["messages"] || []
  end

  defp extract_response_content(response_data) when is_map(response_data) do
    case response_data do
      %{"content" => content} when is_list(content) -> content
      %{"content" => content} when is_binary(content) -> [%{"type" => "text", "text" => content}]
      _ -> []
    end
  end
  defp extract_response_content(_), do: []

  defp render_message_content(content) when is_binary(content), do: content
  defp render_message_content(content) when is_list(content) do
    content
    |> Enum.map(&render_content_block/1)
    |> Enum.join("\n")
  end
  defp render_message_content(_), do: ""

  defp render_content_block(%{"type" => "text", "text" => text}), do: text
  defp render_content_block(%{"type" => "tool_use", "name" => name, "input" => input}) do
    "🔧 **Tool Use: #{name}**\n```json\n#{Jason.encode!(input, pretty: true)}\n```"
  end
  defp render_content_block(_), do: ""

  defp role_color("user"), do: "text-blue-700"
  defp role_color("assistant"), do: "text-green-700"  
  defp role_color("system"), do: "text-purple-700"
  defp role_color(_), do: "text-gray-700"

  defp role_icon("user"), do: "👤"
  defp role_icon("assistant"), do: "🤖"
  defp role_icon("system"), do: "⚙️"
  defp role_icon(_), do: "💬"

  defp status_badge_class("success"), do: "bg-green-100 text-green-800"
  defp status_badge_class("error"), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"
end