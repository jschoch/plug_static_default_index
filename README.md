PlugStaticDefaultIndex
======================

** this is pretty much the same as Plug.Static but takes one additional option called defaultIndex, this defaults to  **

this is pretty much the same as Plug.Static but takes one additional option called defaultIndex, this defaults to "index.html" but you can set it via:

```elixir

defmodule MyPlug do
  use Plug.Builder
  plug Plug.Static, at: "/public", from: :my_app, defaultIndex: "whyIsntIndex.htmlGoodEnough"
  plug :not_found
  def not_found(conn, _) do
    send_resp(conn, 404, "not found")
  end
end

```
