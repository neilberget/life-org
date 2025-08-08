defmodule LifeOrg.EmbeddingsService do
  require Logger
  alias LifeOrg.{Repo, JournalEntry, Todo}
  import Ecto.Query

  @embedding_model "text-embedding-3-small"

  def generate_embedding(text) when is_binary(text) do
    api_key = System.get_env("OPENAI_API_KEY")
    
    if is_nil(api_key) or api_key == "" do
      {:error, :no_api_key}
    else
      openai = OpenaiEx.new(api_key)
      
      case OpenaiEx.Embeddings.create(openai, %{
        model: @embedding_model,
        input: text
      }) do
        {:ok, %{"data" => [%{"embedding" => embedding} | _]}} ->
          {:ok, embedding}
        
        {:error, reason} ->
          Logger.error("Failed to generate embedding: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  def update_journal_entry_embedding(%JournalEntry{} = entry) do
    with {:ok, embedding} <- generate_embedding(entry.content) do
      entry
      |> Ecto.Changeset.change(%{
        embedding: embedding,
        embedding_generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()
    end
  end

  def update_todo_embedding(%Todo{} = todo) do
    text = "#{todo.title} #{todo.description || ""}"
    
    with {:ok, embedding} <- generate_embedding(text) do
      todo
      |> Ecto.Changeset.change(%{
        embedding: embedding,
        embedding_generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update()
    end
  end

  def find_journal_entries_without_embeddings(limit \\ 10) do
    from(j in JournalEntry,
      where: is_nil(j.embedding_generated_at),
      limit: ^limit,
      order_by: [desc: j.inserted_at]
    )
    |> Repo.all()
  end

  def find_todos_without_embeddings(limit \\ 10) do
    from(t in Todo,
      where: is_nil(t.embedding_generated_at),
      limit: ^limit,
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  def cosine_similarity(vec1, vec2) when is_list(vec1) and is_list(vec2) do
    dot_product = Enum.zip(vec1, vec2) |> Enum.reduce(0, fn {a, b}, acc -> acc + a * b end)
    
    magnitude1 = :math.sqrt(Enum.reduce(vec1, 0, fn x, acc -> acc + x * x end))
    magnitude2 = :math.sqrt(Enum.reduce(vec2, 0, fn x, acc -> acc + x * x end))
    
    if magnitude1 == 0 or magnitude2 == 0 do
      0.0
    else
      dot_product / (magnitude1 * magnitude2)
    end
  end

  def search_journal_entries(query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    workspace_id = Keyword.get(opts, :workspace_id)
    
    with {:ok, query_embedding} <- generate_embedding(query_text) do
      base_query = from(j in JournalEntry,
        where: not is_nil(j.embedding),
        preload: [:workspace]
      )
      
      base_query = if workspace_id do
        from(j in base_query, where: j.workspace_id == ^workspace_id)
      else
        base_query
      end
      
      entries = Repo.all(base_query)
      
      entries_with_scores = entries
      |> Enum.map(fn entry ->
        score = cosine_similarity(entry.embedding, query_embedding)
        {entry, score}
      end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)
      |> Enum.take(limit)
      
      {:ok, entries_with_scores}
    end
  end

  def search_todos(query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    workspace_id = Keyword.get(opts, :workspace_id)
    
    with {:ok, query_embedding} <- generate_embedding(query_text) do
      base_query = from(t in Todo,
        where: not is_nil(t.embedding),
        preload: [:workspace]
      )
      
      base_query = if workspace_id do
        from(t in base_query, where: t.workspace_id == ^workspace_id)
      else
        base_query
      end
      
      todos = Repo.all(base_query)
      
      todos_with_scores = todos
      |> Enum.map(fn todo ->
        score = cosine_similarity(todo.embedding, query_embedding)
        {todo, score}
      end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)
      |> Enum.take(limit)
      
      {:ok, todos_with_scores}
    end
  end

  def search_all(query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    workspace_id = Keyword.get(opts, :workspace_id)
    
    with {:ok, journal_results} <- search_journal_entries(query_text, workspace_id: workspace_id, limit: limit),
         {:ok, todo_results} <- search_todos(query_text, workspace_id: workspace_id, limit: limit) do
      
      all_results = 
        (Enum.map(journal_results, fn {entry, score} -> {:journal_entry, entry, score} end) ++
         Enum.map(todo_results, fn {todo, score} -> {:todo, todo, score} end))
        |> Enum.sort_by(fn {_, _, score} -> score end, :desc)
        |> Enum.take(limit)
      
      {:ok, all_results}
    end
  end
end