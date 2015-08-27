ExUnit.start exclude: [:integration]

defmodule HexTest.Case do
  use ExUnit.CaseTemplate

  def tmp_path do
    Path.expand("../tmp", __DIR__)
  end

  def tmp_path(extension) do
    Path.join(tmp_path, extension)
  end

  def fixture_path do
    Path.expand("fixtures", __DIR__)
  end

  def fixture_path(extension) do
    Path.join(fixture_path, extension)
  end

  defmacro in_tmp(fun) do
    path = Path.join(["#{__CALLER__.module}", "#{elem(__CALLER__.function, 0)}"])
    quote do
      in_tmp(unquote(path), unquote(fun))
    end
  end

  defmacro in_fixture(which, fun) do
    path = Path.join(["#{__CALLER__.module}", "#{elem(__CALLER__.function, 0)}"])
    quote do
      in_fixture(unquote(which), unquote(path), unquote(fun))
    end
  end

  def in_tmp(tmp, function) do
    path = tmp_path(tmp)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    File.cd!(path, function)
  end

  def in_fixture(which, tmp, function) do
    tmp = tmp_path(tmp)
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)

    which = fixture_path(which)
    File.cp_r!(which, tmp)

    File.cd!(tmp, function)
  end

  @template """
  defmodule ~s.NoConflict.Mixfile do
    use Mix.Project

    def project do
      [ app: :~s,
        version: "~s",
        deps: deps() ]
    end

    defp deps do
      ~s
    end
  end
  """

  def init_project(name, version, deps, meta, auth) do
    reqs =
      Enum.filter(deps, fn
        {_app, _req, opts} -> !(opts[:path] || opts[:git] || opts[:github])
        _ -> true
      end)

    reqs = Enum.into(reqs, %{}, fn
      {app, req} ->
        {app, %{app: app, requirement: req, optional: false}}
      {app, req, opts} ->
        default_opts = %{app: app, requirement: req, optional: false}
        {opts[:hex] || app, Dict.merge(default_opts, opts)}
    end)

    meta = Map.merge(meta, %{name: name, version: version, requirements: reqs})
    meta = Map.put_new(meta, :app, name)
    meta = Map.put_new(meta, :build_tools, ["mix"])

    deps = inspect(deps, pretty: true)
    module = String.capitalize(name)
    mixfile = :io_lib.format(@template, [module, name, version, deps])

    files = [{"mix.exs", List.to_string(mixfile)}]
    tar = Hex.Tar.create(meta, files)

    {_, %{"name" => ^name}}       = Hex.API.Package.new(name, meta, auth)
    {_, %{"version" => ^version}} = Hex.API.Release.new(name, tar, auth)
  end

  def purge(modules) do
    Enum.each modules, fn(m) ->
      :code.delete(m)
      :code.purge(m)
    end
  end

  @ets_table :hex_ets_registry
  @version   4

  def create_test_registry(path) do
    packages =
      Enum.reduce(test_registry, %{}, fn {name, vsn, _}, dict ->
        Map.update(dict, "#{name}", [vsn], &[vsn|&1])
      end)

    packages =
      Enum.map(packages, fn {name, vsns} ->
        {"#{name}", [Enum.sort(vsns, &(Version.compare(&1, &2) == :lt))]}
      end)

    releases =
      Enum.map(test_registry, fn {name, version, deps} ->
        deps = Enum.map(deps, fn
          {name, req} -> ["#{name}", req, false, "#{name}"]
          {name, req, optional} -> ["#{name}", req, optional, "#{name}"]
          {name, req, optional, app} -> ["#{name}", req, optional, "#{app}"]
        end)
        {{"#{name}", version}, [deps, nil]}
      end)

    create_registry(path, @version, [], releases, packages)
  end

  def create_registry(path, version, installs, releases, packages) do
    tid = :ets.new(@ets_table, [])
    :ets.insert(tid, {:"$$version$$", version})
    :ets.insert(tid, {:"$$installs2$$", installs})
    :ets.insert(tid, releases ++ packages)
    :ok = :ets.tab2file(tid, String.to_char_list(path))
    :ets.delete(tid)
  end

  defp test_registry do
    [ {:foo, "0.0.1", []},
      {:foo, "0.1.0", []},
      {:foo, "0.2.0", []},
      {:foo, "0.2.1", []},
      {:bar, "0.0.1", []},
      {:bar, "0.1.0", [foo: "~> 0.1.0"]},
      {:bar, "0.2.0", [foo: "~> 0.2.0"]},

      {:a, "0.0.1", []},
      {:a, "0.0.2", []},
      {:a, "0.0.3", []},
      {:b, "0.0.1", [a: "~> 0.0.1"]},
      {:b, "0.0.2", [a: "~> 0.0.1"]},
      {:b, "0.1.0", [a: "~> 0.0.1"]},

      {:c, "0.0.1", [a: "~> 0.0.2", b: "~> 0.1.0"]},
      {:c, "0.0.2", [a: "~> 0.0.2", b: "~> 0.1.0"]},
      {:c, "0.0.3", [a: "~> 0.0.2", b: "~> 0.1.0"]},
      {:e, "0.0.1", [c: "~> 0.0.3", b: "~> 0.0.2"]},
      {:d, "0.0.1", [e: "0.0.1", c: "~> 0.0.3", b: "~> 0.0.2"]},

      {:decimal, "0.0.1", []},
      {:decimal, "0.1.0", []},
      {:decimal, "0.2.0", []},
      {:decimal, "0.2.1", []},
      {:ex_plex, "0.0.1", []},
      {:ex_plex, "0.0.2", [decimal: "0.1.1"]},
      {:ex_plex, "0.1.0", [decimal: "~> 0.1.0"]},
      {:ex_plex, "0.1.2", [decimal: "~> 0.1.0"]},
      {:ex_plex, "0.2.0", [decimal: "~> 0.2.0"]},

      {:jose, "0.2.0", []},
      {:jose, "0.2.1", []},
      {:eric, "0.0.1", []},
      {:eric, "0.0.2", []},
      {:eric, "0.1.0", [jose: "~> 0.1.0"]},
      {:eric, "0.1.2", [jose: "~> 0.1.0"]},
      {:eric, "0.2.0", [jose: "~> 0.3.0"]},

      {:ex_doc, "0.0.1", []},
      {:ex_doc, "0.0.2", []},
      {:ex_doc, "0.1.0", []},
      {:postgrex, "0.2.0", [ex_doc: "0.0.1"]},
      {:postgrex, "0.2.1", [ex_doc: "~> 0.1.0"]},
      {:ecto, "0.2.0", [postgrex: "~> 0.2.0", ex_doc: "~> 0.0.1"]},
      {:ecto, "0.2.1", [postgrex: "~> 0.2.1", ex_doc: "0.1.0"]},
      {:phoenix, "0.0.1", [postgrex: "~> 0.2"]},

      {:only_doc, "0.1.0", [{:ex_doc, ">= 0.0.0", true}]},

      {:has_optional, "0.1.0", [{:ex_doc, "~> 0.0.1", true}]},

      {:package_name, "0.1.0", []},
      {:depend_name, "0.2.0", [{:package_name, ">= 0.0.0", false, :app_name}]} ]
  end

  def setup_auth(username) do
    user = HexWeb.User.get(username: username)
    key  = :crypto.rand_bytes(4) |> Base.encode16

    {:ok, key} = HexWeb.API.Key.create(user, %{"name" => key})
    Hex.Config.update([key: key.user_secret])
  end

  using do
    quote do
      import unquote(__MODULE__)
    end
  end

  setup_all do
    ets_path = tmp_path("registry.ets")
    File.rm(ets_path)
    create_test_registry(ets_path)
    :ok
  end

  @registry_tid :registry_tid

  setup do
    Hex.State.put(:home, tmp_path("hex_home"))
    Hex.State.put(:registry_updated, true)
    Hex.Parallel.clear(:hex_fetcher)
    Hex.Registry.close

    Mix.shell(Mix.Shell.Process)
    Mix.Task.clear
    Mix.Shell.Process.flush
    Mix.ProjectStack.clear_cache
    Mix.ProjectStack.clear_stack

    :ok
  end
end

alias HexTest.Case
File.rm_rf!(Case.tmp_path)
File.mkdir_p!(Case.tmp_path)

Application.start(:logger)
Hex.State.put(:api, "http://localhost:4043/api")
unless System.get_env("HEX_CDN"), do: Hex.State.put(:cdn, "http://localhost:4043")


if :integration in ExUnit.configuration[:include] do
  db = "hex_test"
  db_url = "ecto://postgres:postgres@localhost/#{db}"

  System.put_env("DATABASE_URL", db_url)

  File.cd! "_build/test/lib/hex_web", fn ->
    Mix.Task.run "ecto.drop", ["-r", "HexWeb.Repo"]
    Mix.Task.run "ecto.create", ["-r", "HexWeb.Repo"]
    Mix.Task.run "ecto.migrate", ["-r", "HexWeb.Repo"]
  end
  HexWeb.Repo.stop

  {:ok, _} = Application.ensure_all_started(:hex_web)

  pkg_meta = %{
    "contributors" => ["John Doe", "Jane Doe"],
    "licenses" => ["GPL2", "MIT", "Apache"],
    "links" => %{"docs" => "http://docs", "repo" => "http://repo"},
    "description" => "builds docs"}

  rel_meta = %{
    "app" => "ex_doc",
    "build_tools" => ["mix"]
  }

  {:ok, user}    = HexWeb.User.create(%{"username" => "user", "email" => "user@mail.com", "password" => "hunter42"})
  {:ok, package} = HexWeb.Package.create(user, %{"name" => "ex_doc", "meta" => pkg_meta})
  {:ok, _}       = HexWeb.Release.create(package, %{"version" => "0.0.1", "requirements" => %{}, "meta" => rel_meta}, "")

  HexWeb.User.confirm(user)

  {201, %{"secret" => secret}} = Hex.API.Key.new("my_key", [user: "user", pass: "hunter42"])
  auth = [key: secret]

  Case.init_project("ex_doc", "0.0.1", [], pkg_meta, auth)
  Case.init_project("ex_doc", "0.0.1", [], pkg_meta, auth)
  Case.init_project("ex_doc", "0.1.0", [], pkg_meta, auth)
  Case.init_project("postgrex", "0.2.1", [ex_doc: "~> 0.1.0"], %{}, auth)
  Case.init_project("postgrex", "0.2.0", [ex_doc: "0.0.1"], %{}, auth)
  Case.init_project("ecto", "0.2.0", [postgrex: "~> 0.2.0", ex_doc: "~> 0.0.1"], %{}, auth)
  Case.init_project("ecto", "0.2.1", [{:sample, "0.0.1", path: Case.fixture_path("sample")}, postgrex: "~> 0.2.1", ex_doc: "0.1.0"], %{}, auth)
  Case.init_project("phoenix", "0.0.1", [postgrex: "~> 0.2"], %{}, auth)
  Case.init_project("only_doc", "0.1.0", [{:ex_doc, ">= 0.0.0", optional: true}], %{}, auth)
  Case.init_project("package_name", "0.1.0", [], %{app: "app_name"}, auth)
  Case.init_project("depend_name", "0.2.0", [{:app_name, ">= 0.0.0", optional: true, hex: :package_name}], %{}, auth)
end
