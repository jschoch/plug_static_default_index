defmodule Plug.StaticDefaultIndex do
  @moduledoc """

  # See Plug.Static for other options
  this adds one option (defaultIndex) and a check to see if conn.path_info is a directory

  """
  def init(opts) do
    at    = Keyword.fetch!(opts, :at)
    from  = Keyword.fetch!(opts, :from)
    gzip  = Keyword.get(opts, :gzip, false)
    only  = Keyword.get(opts, :only, nil)
    defaultIndex = Keyword.get(opts, :defaultIndex, "index.html")

    qs_cache = Keyword.get(opts, :cache_control_for_vsn_requests, "public, max-age=31536000")
    et_cache = Keyword.get(opts, :cache_control_for_etags, "public")

    from =
      case from do
        {_, _} -> from
        _ when is_atom(from) -> {from, "priv/static"}
        _ when is_binary(from) -> from
        _ -> raise ArgumentError, ":from must be an atom, a binary or a tuple"
      end

    {Plug.Router.Utils.split(at), from, gzip, qs_cache, et_cache, only, defaultIndex}
  end

  def call(conn, {at, from, gzip, qs_cache, et_cache, only, defaultIndex}) do
    opts = {at, from, gzip, qs_cache, et_cache, only}

    case Plug.Static.call(conn, opts) do
      %Plug.Conn{halted: true} = served_static_conn -> served_static_conn
      conn ->
        case Plug.Static.call(put_in(conn.path_info, conn.path_info ++ [defaultIndex]), opts) do
          %Plug.Conn{halted: true} = served_index_conn -> served_index_conn
          _unserved_index_conn -> 
            IO.puts "Path not found #{inspect conn.path_info}"
            conn
        end
    end
  end
end
