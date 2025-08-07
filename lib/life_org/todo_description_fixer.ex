defmodule LifeOrg.TodoDescriptionFixer do
  @moduledoc """
  Helper functions to fix and normalize todo descriptions with checkbox formatting issues.
  """

  alias LifeOrg.{Repo, Todo}
  import Ecto.Query

  @doc """
  Fixes checkbox formatting in all todo descriptions.
  This function cleans up common formatting issues from rich text editor output.
  """
  def fix_all_todo_descriptions do
    from(t in Todo, where: not is_nil(t.description) and t.description != "")
    |> Repo.all()
    |> Enum.each(&fix_todo_description/1)
  end

  @doc """
  Fixes checkbox formatting for a specific todo.
  """
  def fix_todo_description(%Todo{} = todo) do
    if todo.description && String.trim(todo.description) != "" do
      fixed_description = normalize_checkbox_format(todo.description)

      if fixed_description != todo.description do
        {:ok, _} = Repo.update(Ecto.Changeset.change(todo, description: fixed_description))
        IO.puts("Fixed todo #{todo.id}: #{String.slice(todo.title, 0, 50)}...")
      end
    end
  end

  @doc """
  Normalizes checkbox formatting in markdown text.
  """
  def normalize_checkbox_format(description) when is_binary(description) do
    description
    # Remove common escaping issues
    |> String.replace(~r/\\(\[|\])/, "\\1")
    |> String.replace(~r/\\\-/, "-")

    # Fix checkbox spacing issues
    # Add space after empty checkbox
    |> String.replace(~r/- \[\]([^\s])/, "- [ ] \\1")
    # Add space after checked checkbox
    |> String.replace(~r/- \[x\]([^\s])/i, "- [x] \\1")

    # Convert numbered list checkboxes to bullet checkboxes
    |> String.replace(~r/^\s*\d+\.\s*- \[ \]/, "- [ ]")
    |> String.replace(~r/^\s*\d+\.\s*- \[x\]/i, "- [x]")

    # Replace Unicode checkbox symbols with proper markdown
    |> String.replace("□", "- [ ]")
    |> String.replace("☑", "- [x]")
    |> String.replace("✓", "- [x]")
    |> String.replace("✅", "- [x]")

    # Clean up multiple newlines
    |> String.replace(~r/\n\n+/, "\n\n")

    # Ensure proper line formatting for checkboxes
    |> String.split("\n")
    |> Enum.map(&fix_checkbox_line/1)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp fix_checkbox_line(line) do
    trimmed = String.trim(line)

    cond do
      # Already properly formatted
      String.match?(trimmed, ~r/^- \[ \] /) or String.match?(trimmed, ~r/^- \[x\] /i) ->
        line

      # Fix missing space after checkbox
      String.match?(trimmed, ~r/^- \[ \][^ ]/) ->
        String.replace(line, ~r/- \[ \]([^ ])/, "- [ ] \\1")

      String.match?(trimmed, ~r/^- \[x\][^ ]/i) ->
        String.replace(line, ~r/- \[x\]([^ ])/i, "- [x] \\1")

      # Convert other formats
      String.starts_with?(trimmed, "□") ->
        String.replace(line, ~r/^(\s*)□\s*/, "\\1- [ ] ")

      String.starts_with?(trimmed, "☑") ->
        String.replace(line, ~r/^(\s*)☑\s*/, "\\1- [x] ")

      true ->
        line
    end
  end

  @doc """
  Preview what changes would be made to a description without saving.
  """
  def preview_fixes(description) when is_binary(description) do
    original = description
    fixed = normalize_checkbox_format(description)

    %{
      original: original,
      fixed: fixed,
      changed?: original != fixed,
      changes: if(original != fixed, do: diff_lines(original, fixed), else: [])
    }
  end

  defp diff_lines(original, fixed) do
    original_lines = String.split(original, "\n")
    fixed_lines = String.split(fixed, "\n")

    Enum.zip_with([original_lines, fixed_lines], fn [orig, fix] ->
      if orig != fix do
        %{from: orig, to: fix}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
