defmodule Finance.Mixfile do
  use Mix.Project

  def project do
    [
      app: :finance,
      version: "0.0.2",
      elixir: "~> 1.1",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description:
        "A library to calculate Xirr through the bisection method using parallel processes.",
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [applications: [:logger]]
  end

  defp package do
    [
      files: ["lib", "priv", "mix.exs", "README*"],
      maintainers: ["Roberto Trevisan"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/tubedude/finance-elixir"}
    ]
  end

  defp deps do
    [
      {:timex, "~> 3.1"},
      {:ex_doc, "~> 0.12", only: :dev},
      {:excoveralls, "~> 0.8", only: :test},
      {:benchfella, "~> 0.3.0"}
    ]
  end
end
