defmodule LifeOrg.AttachmentService do
  @moduledoc """
  Service for managing file attachments (images) for journal entries and todos.
  """

  import Ecto.Query
  alias LifeOrg.{Repo, Attachment}

  @upload_dir "priv/static/uploads/images"

  @doc """
  Creates an attachment record in the database.
  """
  def create_attachment(attrs) do
    %Attachment{}
    |> Attachment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single attachment by ID for a specific user.
  """
  def get_attachment(id, user_id) do
    Attachment
    |> where([a], a.id == ^id and a.user_id == ^user_id)
    |> Repo.one()
  end

  @doc """
  Lists all attachments for a journal entry.
  """
  def list_journal_attachments(journal_entry_id) do
    Attachment
    |> where([a], a.journal_entry_id == ^journal_entry_id)
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all attachments for a todo.
  """
  def list_todo_attachments(todo_id) do
    Attachment
    |> where([a], a.todo_id == ^todo_id)
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all attachments for a user.
  """
  def list_user_attachments(user_id) do
    Attachment
    |> where([a], a.user_id == ^user_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Deletes an attachment record and its associated file.
  """
  def delete_attachment(%Attachment{} = attachment) do
    # Delete the file from disk
    file_path = get_file_path(attachment.user_id, attachment.filename)
    File.rm(file_path)

    # Delete the database record
    Repo.delete(attachment)
  end

  @doc """
  Deletes all attachments for a journal entry.
  """
  def delete_journal_attachments(journal_entry_id) do
    attachments = list_journal_attachments(journal_entry_id)

    Enum.each(attachments, fn attachment ->
      delete_attachment(attachment)
    end)
  end

  @doc """
  Deletes all attachments for a todo.
  """
  def delete_todo_attachments(todo_id) do
    attachments = list_todo_attachments(todo_id)

    Enum.each(attachments, fn attachment ->
      delete_attachment(attachment)
    end)
  end

  @doc """
  Saves an uploaded file to disk and returns the saved filename.
  Returns {:ok, filename} or {:error, reason}.
  """
  def save_upload(user_id, %{path: temp_path, filename: original_filename}) do
    # Ensure user directory exists
    user_dir = get_user_dir(user_id)
    File.mkdir_p!(user_dir)

    # Generate unique filename
    uuid = Ecto.UUID.generate()
    extension = Path.extname(original_filename)
    filename = "#{uuid}#{extension}"

    # Copy file to destination
    destination = Path.join(user_dir, filename)

    case File.cp(temp_path, destination) do
      :ok -> {:ok, filename}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns the full filesystem path for a user's upload directory.
  """
  def get_user_dir(user_id) do
    Path.join(@upload_dir, to_string(user_id))
  end

  @doc """
  Returns the full filesystem path for a specific file.
  """
  def get_file_path(user_id, filename) do
    Path.join(get_user_dir(user_id), filename)
  end

  @doc """
  Returns the web-accessible URL path for an uploaded file.
  """
  def get_url_path(user_id, filename) do
    "/uploads/images/#{user_id}/#{filename}"
  end

  @doc """
  Cleans up orphaned attachments (files that exist but have no database record).
  This is a maintenance function that can be run periodically.
  """
  def cleanup_orphaned_files(user_id) do
    user_dir = get_user_dir(user_id)

    if File.exists?(user_dir) do
      # Get all files in user directory
      {:ok, files} = File.ls(user_dir)

      # Get all attachment filenames from database
      attachment_filenames =
        list_user_attachments(user_id)
        |> Enum.map(& &1.filename)
        |> MapSet.new()

      # Delete files that don't have database records
      orphaned_files =
        files
        |> Enum.reject(&MapSet.member?(attachment_filenames, &1))

      Enum.each(orphaned_files, fn file ->
        File.rm(Path.join(user_dir, file))
      end)

      {:ok, length(orphaned_files)}
    else
      {:ok, 0}
    end
  end
end
