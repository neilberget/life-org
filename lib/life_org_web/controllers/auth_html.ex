defmodule LifeOrgWeb.AuthHTML do
  @moduledoc """
  HTML templates for authentication and integration settings.
  """
  
  use LifeOrgWeb, :html

  embed_templates "auth_html/*"
end