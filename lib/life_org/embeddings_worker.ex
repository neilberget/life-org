defmodule LifeOrg.EmbeddingsWorker do
  use GenServer
  require Logger
  alias LifeOrg.EmbeddingsService

  @check_interval :timer.seconds(30)
  @batch_size 5

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Logger.info("EmbeddingsWorker started")
    schedule_work()
    {:ok, %{}}
  end

  def handle_info(:process_embeddings, state) do
    process_missing_embeddings()
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work do
    Process.send_after(self(), :process_embeddings, @check_interval)
  end

  defp process_missing_embeddings do
    Logger.debug("Checking for content without embeddings...")
    
    journal_entries = EmbeddingsService.find_journal_entries_without_embeddings(@batch_size)
    todos = EmbeddingsService.find_todos_without_embeddings(@batch_size)
    
    total_count = length(journal_entries) + length(todos)
    
    if total_count > 0 do
      Logger.info("Processing #{total_count} items for embeddings (#{length(journal_entries)} journal entries, #{length(todos)} todos)")
      
      Enum.each(journal_entries, fn entry ->
        case EmbeddingsService.update_journal_entry_embedding(entry) do
          {:ok, _updated_entry} ->
            Logger.debug("Generated embedding for journal entry #{entry.id}")
          {:error, :content_too_long} ->
            # Mark as processed with an empty embedding so we don't retry
            Logger.warning("Journal entry #{entry.id} is too long for embeddings (#{String.length(entry.content)} chars), marking as processed")
            mark_journal_entry_as_skipped(entry)
          {:error, :no_api_key} ->
            # Don't log error for missing API key (already logged at startup)
            :ok
          {:error, reason} ->
            Logger.error("Failed to generate embedding for journal entry #{entry.id}: #{inspect(reason)}")
        end

        Process.sleep(100)
      end)

      Enum.each(todos, fn todo ->
        case EmbeddingsService.update_todo_embedding(todo) do
          {:ok, _updated_todo} ->
            Logger.debug("Generated embedding for todo #{todo.id}")
          {:error, :content_too_long} ->
            # Mark as processed with an empty embedding so we don't retry
            text_length = String.length("#{todo.title} #{todo.description || ""}")
            Logger.warning("Todo #{todo.id} is too long for embeddings (#{text_length} chars), marking as processed")
            mark_todo_as_skipped(todo)
          {:error, :no_api_key} ->
            # Don't log error for missing API key (already logged at startup)
            :ok
          {:error, reason} ->
            Logger.error("Failed to generate embedding for todo #{todo.id}: #{inspect(reason)}")
        end

        Process.sleep(100)
      end)
    end
  end

  defp mark_journal_entry_as_skipped(entry) do
    entry
    |> Ecto.Changeset.change(%{
      embedding: [],
      embedding_generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> LifeOrg.Repo.update()
  end

  defp mark_todo_as_skipped(todo) do
    todo
    |> Ecto.Changeset.change(%{
      embedding: [],
      embedding_generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> LifeOrg.Repo.update()
  end

  def trigger_processing do
    GenServer.cast(__MODULE__, :trigger_processing)
  end

  def handle_cast(:trigger_processing, state) do
    process_missing_embeddings()
    {:noreply, state}
  end
end