defmodule LifeOrg.TimezoneHelper do
  @moduledoc """
  Helper functions for timezone conversions throughout the application.
  """
  
  @doc """
  Converts a UTC datetime to the user's local timezone.
  Returns the converted datetime or the original if conversion fails.
  """
  def to_user_timezone(nil, _timezone), do: nil
  
  def to_user_timezone(datetime, nil) do
    # Default to America/Chicago if no timezone is set
    to_user_timezone(datetime, "America/Chicago")
  end
  
  def to_user_timezone(%NaiveDateTime{} = naive_datetime, timezone) when is_binary(timezone) do
    naive_datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> to_user_timezone(timezone)
  end

  def to_user_timezone(%DateTime{} = datetime, timezone) when is_binary(timezone) do
    case DateTime.shift_zone(datetime, timezone) do
      {:ok, converted} -> converted
      {:error, _} -> datetime
    end
  end
  
  @doc """
  Formats a datetime in the user's timezone with a standard format.
  """
  def format_datetime(nil, _timezone), do: ""
  
  def format_datetime(datetime, timezone) do
    datetime
    |> to_user_timezone(timezone)
    |> Calendar.strftime("%m/%d/%Y %I:%M %p")
  end
  
  @doc """
  Formats a date in the user's timezone.
  """
  def format_date(nil, _timezone), do: ""
  
  def format_date(%Date{} = date, _timezone) do
    Calendar.strftime(date, "%m/%d/%Y")
  end
  
  def format_date(datetime, timezone) do
    datetime
    |> to_user_timezone(timezone)
    |> DateTime.to_date()
    |> Calendar.strftime("%m/%d/%Y")
  end
  
  @doc """
  Formats a time in the user's timezone.
  """
  def format_time(nil, _timezone), do: ""
  
  def format_time(datetime, timezone) do
    datetime
    |> to_user_timezone(timezone)
    |> Calendar.strftime("%I:%M %p")
  end
  
  @doc """
  Returns a list of common US timezones for selection.
  """
  def us_timezones do
    [
      {"Eastern Time (EST/EDT)", "America/New_York"},
      {"Central Time (CST/CDT)", "America/Chicago"},
      {"Mountain Time (MST/MDT)", "America/Denver"},
      {"Pacific Time (PST/PDT)", "America/Los_Angeles"},
      {"Alaska Time", "America/Anchorage"},
      {"Hawaii Time", "Pacific/Honolulu"},
      {"Arizona Time", "America/Phoenix"}
    ]
  end
  
end