defmodule LifeOrgWeb.API.V1.JournalEntryJSON do
  alias LifeOrg.JournalEntry

  def index(%{journal_entries: journal_entries}) do
    %{data: for(entry <- journal_entries, do: data(entry))}
  end

  def show(%{journal_entry: journal_entry}) do
    %{data: data(journal_entry)}
  end

  defp data(%JournalEntry{} = entry) do
    %{
      id: entry.id,
      content: entry.content,
      entry_date: entry.entry_date,
      tags: entry.tags || [],
      workspace_id: entry.workspace_id,
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end
end
