defmodule LifeOrg.Repo.Migrations.CreateApiLogsTable do
  use Ecto.Migration

  def change do
    create table(:api_logs) do
      add :service, :string, null: false # e.g., "anthropic"
      add :model, :string, null: false # e.g., "claude-sonnet-4-0"
      add :request_data, :json, null: false # full request payload
      add :response_data, :json # full response payload (null if error)
      add :status, :string, null: false # "success" or "error"
      add :error_message, :text # error details if status is error
      add :input_tokens, :integer # tokens in request
      add :output_tokens, :integer # tokens in response
      add :total_tokens, :integer # sum of input + output tokens
      add :duration_ms, :integer # request duration in milliseconds
      add :user_id, :integer # future use for multi-user support
      
      timestamps()
    end
    
    create index(:api_logs, [:service])
    create index(:api_logs, [:model])
    create index(:api_logs, [:status])
    create index(:api_logs, [:inserted_at])
  end
end
