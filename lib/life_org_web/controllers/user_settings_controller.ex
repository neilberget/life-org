defmodule LifeOrgWeb.UserSettingsController do
  use LifeOrgWeb, :controller

  alias LifeOrg.Accounts
  alias LifeOrg.ApiTokens
  alias LifeOrgWeb.UserAuth

  plug :assign_email_and_password_changesets

  def edit(conn, _params) do
    render(conn, :edit)
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"current_password" => password, "user" => user_params} = params
    user = conn.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: ~p"/users/settings")

      {:error, changeset} ->
        render(conn, :edit, email_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"current_password" => password, "user" => user_params} = params
    user = conn.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> put_session(:user_return_to, ~p"/users/settings")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, :edit, password_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "update_timezone"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_user

    case Accounts.update_user_timezone(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Timezone updated successfully.")
        |> redirect(to: ~p"/users/settings")

      {:error, changeset} ->
        render(conn, :edit, timezone_changeset: changeset)
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_user, token) do
      :ok ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: ~p"/users/settings")

      :error ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  def create_api_token(conn, %{"api_token" => %{"name" => name}}) do
    user = conn.assigns.current_user

    case ApiTokens.create_token(user, %{"name" => name}) do
      {:ok, _api_token, token} ->
        conn
        |> put_flash(:info, "API token created successfully. Copy it now - you won't see it again!")
        |> put_flash(:token, token)
        |> redirect(to: ~p"/users/settings")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to create API token.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  def delete_api_token(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case ApiTokens.delete_token(id, user.id) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "API token deleted successfully.")
        |> redirect(to: ~p"/users/settings")

      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to delete API token.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns.current_user

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
    |> assign(:timezone_changeset, Accounts.change_user_timezone(user))
    |> assign(:timezones, LifeOrg.TimezoneHelper.us_timezones())
    |> assign(:api_tokens, ApiTokens.list_tokens_for_user(user.id))
  end
end
