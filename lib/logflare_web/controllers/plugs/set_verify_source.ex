defmodule LogflareWeb.Plugs.SetVerifySource do
  @moduledoc """
  Verifies user ownership of a source for browser only
  """
  use Plug.Builder

  import Plug.Conn
  import Phoenix.Controller
  alias Logflare.{Sources, Source}

  def call(%{assigns: %{source: %Source{}}} = conn, _opts), do: conn

  def call(%{request_path: "/sources/public/" <> public_token} = conn, opts) do
    set_source_for_public(public_token, conn, opts)
  end

  def call(%{assigns: %{user: user}, params: params} = conn, _opts) do
    id = params["source_id"] || params["id"]
    source = Sources.get_by_and_preload(id: id)
    user_authorized? = &(&1.user_id === user.id || user.admin)

    case source && user_authorized?.(source) do
      true ->
        assign(conn, :source, source)

      false ->
        conn
        |> put_status(403)
        |> put_layout(false)
        |> put_view(LogflareWeb.ErrorView)
        |> render("403_page.html")
        |> halt()

      _ ->
        conn
        |> put_status(404)
        |> put_layout(false)
        |> put_view(LogflareWeb.ErrorView)
        |> render("404_page.html")
        |> halt()
    end
  end

  defp set_source_for_public(public_token, conn, _opts) do
    case Sources.Cache.get_by_and_preload(public_token: public_token) do
      nil ->
        conn
        |> put_status(404)
        |> put_layout(false)
        |> put_view(LogflareWeb.ErrorView)
        |> render("404_page.html")
        |> halt()

      source ->
        assign(conn, :source, source)
    end
  end
end
