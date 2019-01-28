defmodule K8s.Client.Runner.BaseTest do
  use ExUnit.Case, async: true
  doctest K8s.Client.Runner.Base

  alias K8s.Client
  alias K8s.Client.Runner.Base

  setup do
    bypass = Bypass.open()

    conf = K8s.Conf.from_file("test/support/kube-config.yaml")
    conf = %{conf | url: "http://localhost:#{bypass.port}/"}
    cluster = K8s.Cluster.register("base-test", conf)

    {:ok, bypass: bypass, cluster: cluster}
  end

  def namespace_manifest() do
    %{
      "apiVersion" => "v1",
      "metadata" => %{"name" => "test"},
      "kind" => "Namespace"
    }
  end

  def noop(), do: Jason.encode!(%{})

  describe "run/3" do
    test "running an operation without an HTTP body", %{cluster: cluster, bypass: bypass} do
      Bypass.expect_once(bypass, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v1/namespaces/test"
        Plug.Conn.resp(conn, 200, noop())
      end)

      operation = Client.get(namespace_manifest())
      assert {:ok, _} = Base.run(operation, cluster)
    end

    test "running an operation with an HTTP body", %{cluster: cluster, bypass: bypass} do
      Bypass.expect_once(bypass, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v1/namespaces"
        Plug.Conn.resp(conn, 200, noop())
      end)

      operation = Client.create(namespace_manifest())
      assert {:ok, _} = Base.run(operation, cluster)
    end

    test "running an operation with options", %{cluster: cluster, bypass: bypass} do
      Bypass.expect_once(bypass, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/v1/namespaces/test"
        assert conn.query_string == "watch=true"
        Plug.Conn.resp(conn, 200, noop())
      end)

      operation = Client.get(namespace_manifest())
      opts = [params: %{"watch" => "true"}]
      assert {:ok, _} = Base.run(operation, cluster, opts)
    end
  end

  describe "run/4" do
    test "running an operation with a custom HTTP body", %{cluster: cluster, bypass: bypass} do
      Bypass.expect_once(bypass, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v1/namespaces"

        {:ok, json, _} = Plug.Conn.read_body(conn)
        body = Jason.decode!(json)
        assert body["metadata"]["labels"]["env"] == "test"
        Plug.Conn.resp(conn, 200, noop())
      end)

      # This is a silly example.
      operation = Client.create(namespace_manifest())
      labels = %{"env" => "test"}
      body = put_in(namespace_manifest(), ["metadata", "labels"], labels)

      assert {:ok, _} = Base.run(operation, cluster, body)
    end

    test "running an operation with a custom HTTP body and options", %{
      cluster: cluster,
      bypass: bypass
    } do
      Bypass.expect_once(bypass, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/v1/namespaces"
        assert conn.query_string == "watch=true"

        {:ok, json, _} = Plug.Conn.read_body(conn)
        body = Jason.decode!(json)
        assert body["metadata"]["labels"]["env"] == "test"
        Plug.Conn.resp(conn, 200, noop())
      end)

      # This is a silly example.
      operation = Client.create(namespace_manifest())
      labels = %{"env" => "test"}
      body = put_in(namespace_manifest(), ["metadata", "labels"], labels)
      opts = [params: %{"watch" => "true"}]
      assert {:ok, _} = Base.run(operation, cluster, body, opts)
    end
  end

  describe "run" do
    test "request with HTTP 2xx response with no body", %{cluster: cluster, bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.resp(conn, 201, "")
      end)

      operation = Client.list("v1", "Namespace", [])
      assert {:ok, nil} = Base.run(operation, cluster)
    end

    test "request with HTTP 404 response", %{cluster: cluster, bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.resp(conn, 404, "File not found.")
      end)

      operation = Client.list("v1", "Namespace", [])
      assert {:error, :not_found} = Base.run(operation, cluster)
    end

    test "request with HTTP 401 response", %{cluster: cluster, bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Plug.Conn.resp(conn, 401, "Unauthorized.")
      end)

      operation = Client.list("v1", "Namespace", [])
      assert {:error, :unauthorized} = Base.run(operation, cluster)
    end
  end
end
