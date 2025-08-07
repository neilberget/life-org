defmodule LifeOrg.ApiLog do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "api_logs" do
    field :service, :string
    field :model, :string
    field :request_data, :map
    field :response_data, :map
    field :status, :string
    field :error_message, :string
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :total_tokens, :integer
    field :duration_ms, :integer
    field :user_id, :integer

    timestamps()
  end

  @doc false
  def changeset(api_log, attrs) do
    api_log
    |> cast(attrs, [
      :service,
      :model,
      :request_data,
      :response_data,
      :status,
      :error_message,
      :input_tokens,
      :output_tokens,
      :total_tokens,
      :duration_ms,
      :user_id
    ])
    |> validate_required([:service, :model, :request_data, :status])
    |> validate_inclusion(:status, ["success", "error"])
  end

  @doc "Create a successful API log entry"
  def log_success(attrs) do
    attrs
    |> Map.put(:status, "success")
    |> then(&%__MODULE__{} |> changeset(&1) |> LifeOrg.Repo.insert())
  end

  @doc "Create an error API log entry"
  def log_error(attrs) do
    attrs
    |> Map.put(:status, "error")
    |> then(&%__MODULE__{} |> changeset(&1) |> LifeOrg.Repo.insert())
  end

  @doc "Get recent API logs with pagination"
  def recent_logs(limit \\ 50, offset \\ 0) do
    from(log in __MODULE__,
      order_by: [desc: log.inserted_at],
      limit: ^limit,
      offset: ^offset
    )
    |> LifeOrg.Repo.all()
  end

  @doc "Get API logs filtered by service"
  def logs_by_service(service, limit \\ 50, offset \\ 0) do
    from(log in __MODULE__,
      where: log.service == ^service,
      order_by: [desc: log.inserted_at],
      limit: ^limit,
      offset: ^offset
    )
    |> LifeOrg.Repo.all()
  end

  @doc "Get API usage statistics"
  def usage_stats do
    from(log in __MODULE__,
      select: %{
        total_requests: count(log.id),
        success_count: sum(fragment("CASE WHEN status = 'success' THEN 1 ELSE 0 END")),
        error_count: sum(fragment("CASE WHEN status = 'error' THEN 1 ELSE 0 END")),
        total_input_tokens: sum(log.input_tokens),
        total_output_tokens: sum(log.output_tokens),
        total_tokens: sum(log.total_tokens),
        avg_duration_ms: avg(log.duration_ms)
      }
    )
    |> LifeOrg.Repo.one()
  end
end