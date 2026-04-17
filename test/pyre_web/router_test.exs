defmodule PyreWeb.RouterTest do
  use ExUnit.Case, async: true

  alias PyreWeb.Router

  test "default session options" do
    {_name, session_opts, _route_opts} = Router.__options__([])

    assert session_opts[:session] == {PyreWeb.Router, :__session__, []}
    assert session_opts[:root_layout] == {PyreWeb.LayoutView, :root}
    refute Keyword.has_key?(session_opts, :on_mount)
  end

  test "default route options" do
    {_name, _session_opts, route_opts} = Router.__options__([])

    assert route_opts[:private] == %{live_socket_path: "/live"}
    assert route_opts[:as] == :pyre_web
  end

  test "default live_session_name" do
    {name, _session_opts, _route_opts} = Router.__options__([])
    assert name == :pyre_web
  end

  test "configures on_mount" do
    {_name, session_opts, _route_opts} = Router.__options__(on_mount: [{Foo, :bar}])
    assert session_opts[:on_mount] == [{Foo, :bar}]
  end

  test "configures live_socket_path" do
    {_name, _session_opts, route_opts} = Router.__options__(live_socket_path: "/custom/live")
    assert route_opts[:private] == %{live_socket_path: "/custom/live"}
  end

  test "configures live_session_name" do
    {name, _session_opts, _route_opts} = Router.__options__(live_session_name: :custom)
    assert name == :custom
  end

  test "stores prefix on router module" do
    assert PyreWeb.Test.Router.__pyre_web_prefix__() == "/pyre"
  end
end
