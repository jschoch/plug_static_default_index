PlugStaticDefaultIndex
======================

** turn get "/foo" into get "/foo/index.html" automagically  **

this is pretty much the same as Plug.Static but takes one additional option called defaultIndex, this defaults to "index.html" but you can set it via:

```elixir

defmodule MyPlug do
  use Plug.Builder
  plug Plug.StaticDefaultIndex, 
    at: "/public", 
    from: :my_app, 
    defaultIndex: "whyIsntIndex.htmlNotGoodEnough"
    
end

```

