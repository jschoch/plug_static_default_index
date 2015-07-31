defmodule Plug.StaticDefaultIndexTest do
  use ExUnit.Case, async: true
  use Plug.Test

  defmodule MyPlug do
    use Plug.Builder

    plug Plug.StaticDefaultIndex,
      at: "/public",
      from: Path.expand(".", __DIR__),
      gzip: true

    plug :passthrough

    defp passthrough(conn, _), do:
      Plug.Conn.send_resp(conn, 404, "Passthrough")
  end

  defp call(conn), do: MyPlug.call(conn, [])

  test "serves the file" do
    conn = conn(:get, "/public/fixtures/static.txt") |> call
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-type")  == ["text/plain"]
  end

  test "serves the file with a urlencoded filename" do
    conn = conn(:get, "/public/fixtures/static%20with%20spaces.txt") |> call
    assert conn.status == 200
    assert conn.resp_body == "SPACES"
    assert get_resp_header(conn, "content-type")  == ["text/plain"]
  end

  test "performs etag negotiation" do
    conn = conn(:get, "/public/fixtures/static.txt") |> call
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-type")  == ["text/plain"]

    assert [etag] = get_resp_header(conn, "etag")
    assert get_resp_header(conn, "cache-control")  == ["public"]

    conn = conn(:get, "/public/fixtures/static.txt", nil)
           |> put_req_header("if-none-match", etag)
           |> call
    assert conn.status == 304
    assert conn.resp_body == ""
    assert get_resp_header(conn, "cache-control")  == ["public"]

    assert get_resp_header(conn, "content-type")  == []
    assert get_resp_header(conn, "etag") == [etag]
  end

  test "sets the cache-control_for_vsn_requests when there's a query string" do
    conn = conn(:get, "/public/fixtures/static.txt?vsn=bar") |> call
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-type")  == ["text/plain"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000"]
    assert get_resp_header(conn, "etag") == []
  end

  test "doesn't set cache control headers" do
    opts =
      [at: "/public",
      from: Path.expand(".", __DIR__),
      cache_control_for_vsn_requests: nil,
      cache_control_for_etags: nil]

    conn = conn(:get, "/public/fixtures/static.txt")
           |> Plug.StaticDefaultIndex.call(Plug.StaticDefaultIndex.init(opts))

    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
    assert get_resp_header(conn, "etag") ==[]
  end

  test "passes through on other paths" do
    conn = conn(:get, "/another/fallback.txt") |> call
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
  end

  test "passes through on non existing files" do
    conn = conn(:get, "/public/fixtures/unknown.txt") |> call
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
  end

  test "adds default index on directories" do
    conn = conn(:get, "/public/fixtures") |> call
    assert conn.path_info ==  ~w(public fixtures index.html)
    assert conn.status == 200
    #assert conn.resp_body == "Passthrough"
  end

  test "passes for non-get/non-head requests" do
    conn = conn(:post, "/public/fixtures/static.txt") |> call
    assert conn.status == 404
    assert conn.resp_body == "Passthrough"
  end

  test "returns 400 for unsafe paths" do
    exception = assert_raise Plug.StaticDefaultIndex.InvalidPathError,
                             "invalid path for static asset", fn ->
      conn(:get, "/public/fixtures/../fixtures/static/file.txt") |> call
    end

    assert Plug.Exception.status(exception) == 400

    exception = assert_raise Plug.StaticDefaultIndex.InvalidPathError,
                             "invalid path for static asset", fn ->
      conn(:get, "/public/c:\\foo.txt") |> call
    end

    assert Plug.Exception.status(exception) == 400
  end

  test "serves gzipped file" do
    conn = conn(:get, "/public/fixtures/static.txt", [])
           |> put_req_header("accept-encoding", "gzip")
           |> call
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-encoding") == ["gzip"]
    assert get_resp_header(conn, "vary") == ["Accept-Encoding"]

    conn = conn(:get, "/public/fixtures/static.txt", [])
           |> put_req_header("accept-encoding", "*")
           |> put_resp_header("vary", "Whatever")
           |> call
    assert conn.status == 200
    assert conn.resp_body == "HELLO"
    assert get_resp_header(conn, "content-encoding") == ["gzip"]
    assert get_resp_header(conn, "vary") == ["Accept-Encoding", "Whatever"]
  end

  test "only serves gzipped file if available" do
    conn = conn(:get, "/public/fixtures/static%20with%20spaces.txt", [])
           |> put_req_header("accept-encoding", "gzip")
           |> call
    assert conn.status == 200
    assert conn.resp_body == "SPACES"
    assert get_resp_header(conn, "content-encoding") != ["gzip"]
    assert get_resp_header(conn, "vary") == ["Accept-Encoding"]
  end

  test "raises an exception if :from isn't a binary or an atom" do
    assert_raise ArgumentError, fn ->
      defmodule ExceptionPlug do
        use Plug.Builder
        plug Plug.StaticDefaultIndex, from: 42, at: "foo"
      end
    end
  end

  defmodule FilterPlug do
    use Plug.Builder

    plug Plug.StaticDefaultIndex,
      at: "/",
      from: Path.expand("./fixtures", __DIR__),
      only: ~w(testdir index.html static.txt)

    plug :passthrough

    defp passthrough(conn, _), do:
      Plug.Conn.send_resp(conn, 404, "Passthrough")
  end


  test "serves only allowed files file" do
    #conn = conn(:get, "/static.txt") |> FilterPlug.call([])
    #assert conn.status == 200, "bad status code conn was: #{inspect conn, pretty: true}"

    conn = conn(:get, "/not_in_only.html") |> FilterPlug.call([])
    assert conn.status == 404, "bad status code: #{inspect conn.status} conn was: #{inspect conn, pretty: true}"

    conn = conn(:get, "/static.txt") |> FilterPlug.call([])
    assert conn.status == 200

    conn = conn(:get, "/testdir") |> FilterPlug.call([])
    assert conn.path_info == ~w(testdir index.html)

    conn = conn(:get, "/index.html") |> FilterPlug.call([])
    assert conn.path_info == ["index.html"], "bad status code conn was: #{inspect conn, pretty: true}"

    conn = conn(:get, "/") |> FilterPlug.call([])
    assert conn.path_info == ["index.html"]#, "bad status code conn was: #{inspect conn, pretty: true}"

    conn = conn(:get, "/plug/conn_test.exs") |> FilterPlug.call([])
    assert conn.status == 404
  end
end
