defmodule LifeOrgWeb.MarkdownHelper do
  def render_markdown(nil), do: ""
  
  def render_markdown(content) do
    case Earmark.as_html(content) do
      {:ok, html, _} -> {:safe, html}
      {:error, _} -> content
    end
  end
end