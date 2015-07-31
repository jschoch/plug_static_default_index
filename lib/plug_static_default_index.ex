defmodule Plug.StaticDefaultIndex do
  @moduledoc """
  # See Plug.Static for other options

  this adds one option (defaultIndex) and a check to see if conn.path_info is a directory

  

  """
  @behaviour Plug
  @allowed_methods ~w(GET HEAD)

  import Plug.Conn
  alias Plug.Conn

  require Record
  Record.defrecordp :file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl")

  defmodule InvalidPathError do
    defexception message: "invalid path for static asset", plug_status: 400
  end

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

  def call(conn = %Conn{method: meth}, {at, from, gzip, qs_cache, et_cache, only, defaultIndex})
      when meth in @allowed_methods do
    # subset/2 returns the segments in `conn.path_info` without the
    # segments at the beginning that are shared with `at`.
    segments = subset(at, conn.path_info) |> Enum.map(&URI.decode/1)

    if (segments == []) do 
      segments = [defaultIndex] 
      conn = Map.put(conn,:path_info,[defaultIndex])
    end
    cond do
      not allowed?(only, segments) ->
        conn
      invalid_path?(segments) ->
        raise InvalidPathError
      true ->
        path = path(from, segments)
        serve_static(file_encoding(conn, path, gzip, defaultIndex), segments, gzip, qs_cache, et_cache)
    end
  end

  def call(conn, _opts) do
    conn
  end

  #defp allowed?(_only, []),   do: false
  defp allowed?(_only, []), do: true
  defp allowed?(nil, _list),  do: true
  defp allowed?(only, [h|_]), do: h in only

  defp serve_static({:ok, conn, file_info, path}, segments, gzip, qs_cache, et_cache) do
    case put_cache_header(conn, qs_cache, et_cache, file_info) do
      {:stale, conn} ->
        content_type = segments |> List.last |> Plug.MIME.path

        conn
        |> maybe_add_vary(gzip)
        |> put_resp_header("content-type", content_type)
        |> send_file(200, path)
        |> halt
      {:fresh, conn} ->
        conn
        |> send_resp(304, "")
        |> halt
    end
  end

  defp serve_static({:error, conn}, _segments, _gzip, _qs_cache, _et_cache) do
    conn
  end

  defp maybe_add_vary(conn, true) do
    # If we serve gzip at any moment, we need to set the proper vary
    # header regardless of whether we are serving gzip content right now.
    # See: http://www.fastly.com/blog/best-practices-for-using-the-vary-header/
    update_in conn.resp_headers, &[{"vary", "Accept-Encoding"}|&1]
  end

  defp maybe_add_vary(conn, false) do
    conn
  end

  defp put_cache_header(%Conn{query_string: "vsn=" <> _} = conn, qs_cache, _et_cache, _file_info)
      when is_binary(qs_cache) do
    {:stale, put_resp_header(conn, "cache-control", qs_cache)}
  end

  defp put_cache_header(conn, _qs_cache, et_cache, file_info) when is_binary(et_cache) do
    etag = etag_for_path(file_info)

    conn =
      conn
      |> put_resp_header("cache-control", et_cache)
      |> put_resp_header("etag", etag)

    if etag in get_req_header(conn, "if-none-match") do
      {:fresh, conn}
    else
      {:stale, conn}
    end
  end

  defp put_cache_header(conn, _, _, _) do
    {:stale, conn}
  end

  defp etag_for_path(file_info) do
    file_info(size: size, mtime: mtime) = file_info
    {size, mtime} |> :erlang.phash2() |> Integer.to_string(16)
  end

  defp file_encoding(conn, path, gzip, defaultIndex) do
    #IO.puts path <> inspect conn.path_info
    path_gz = path <> ".gz"
    {test,res} = regular_file_info(path)
    # hanlde gzip
    if (gzip && gzip?(conn)) do
      case regular_file_info(path_gz) do
        {:file, file_info} ->
          IO.puts "should gzip"
          {:ok, put_resp_header(conn, "content-encoding", "gzip"), file_info, path_gz}
        _ -> {:error,conn}
      end
    end
    # handle file and dir check
    cond do
      :file == test ->
        {:ok, conn, res, path}
      :dir == test->
        #IO.puts "dir path #{path} adding defaultIndex: " <> defaultIndex <> inspect conn.path_info
        path = path <> "/" <> defaultIndex
        conn = Map.put(conn,:path_info , conn.path_info ++ [defaultIndex])
        {:ok, conn, res, path}
      true ->
        {:error, conn}
    end
  end

  defp regular_file_info(path) do
    case :prim_file.read_file_info(path) do
      {:ok, file_info(type: :regular) = fi} ->
        {:file,fi}
      {:ok, file_info(type: :directory) = fi} ->
        {:dir,fi}
      doh ->
        #IO.puts "nil for path: " <> path <> " doh!: " <> inspect doh
        {:enoent, file_info()}
    end
  end

  defp gzip?(conn) do
    gzip_header? = &String.contains?(&1, ["gzip", "*"])
    Enum.any? get_req_header(conn, "accept-encoding"), fn accept ->
      accept |> Plug.Conn.Utils.list() |> Enum.any?(gzip_header?)
    end
  end

  defp path({app, from}, segments) when is_atom(app) and is_binary(from),
    do: Path.join([Application.app_dir(app), from|segments])
  defp path(from, segments),
    do: Path.join([from|segments])

  defp subset([h|expected], [h|actual]),
    do: subset(expected, actual)
  defp subset([], actual),
   do: actual
  defp subset(_, _),
    do: []

  defp invalid_path?([h|_]) when h in [".", "..", ""], do: true
  defp invalid_path?([h|t]), do: String.contains?(h, ["/", "\\", ":"]) or invalid_path?(t)
  defp invalid_path?([]), do: false
end
