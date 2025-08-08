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
          {:error, reason} ->
            Logger.error("Failed to generate embedding for journal entry #{entry.id}: #{inspect(reason)}")
        end
        
        Process.sleep(100)
      end)
      
      Enum.each(todos, fn todo ->
        case EmbeddingsService.update_todo_embedding(todo) do
          {:ok, _updated_todo} ->
            Logger.debug("Generated embedding for todo #{todo.id}")
          {:error, reason} ->
            Logger.error("Failed to generate embedding for todo #{todo.id}: #{inspect(reason)}")
        end
        
        Process.sleep(100)
      end)
    end
  end

  def trigger_processing do
    GenServer.cast(__MODULE__, :trigger_processing)
  end

  def handle_cast(:trigger_processing, state) do
    process_missing_embeddings()
    {:noreply, state}
  end
end