defmodule Plug.StaticDefaultIndex.Mixfile do
  use Mix.Project

  def project do
    [app: :plug_static_default_index,
     version: "0.0.1",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [ applications: [:logger],
      mod: {Plug, []} 
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
    {:plug, "~> 0.14"},
    {:hackney, "~> 1.2.0", only: :test}
    ]
  end
end
