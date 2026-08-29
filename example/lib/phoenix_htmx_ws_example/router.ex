defmodule PhoenixHtmxWsExample.Router do
  use Plug.Router

  alias PhoenixHtmxWsExample.{Chat, ChatComponents}

  plug(:match)
  plug(:load_session)
  plug(Plug.CSRFProtection)
  plug(:dispatch)

  get "/" do
    room_id = "general"

    html =
      ChatComponents.page(%{
        messages: Chat.list_messages(room_id),
        connect_path: PhoenixHtmxWs.connect_path("/htmx/chat/#{room_id}")
      })
      |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, html)
  end

  get "/browser/:mode" do
    room_id = "browser-#{mode}"

    html =
      ChatComponents.browser_fixture(%{
        mode: mode,
        connect_path: PhoenixHtmxWs.connect_path("/htmx/chat/#{room_id}")
      })
      |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, html)
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end

  defp load_session(conn, _opts), do: Plug.Conn.fetch_session(conn)
end

defmodule PhoenixHtmxWsExample.ErrorHTML do
  def render(_template, _assigns), do: "Internal server error"
end
