defmodule CorroCLI.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/your-org/corro_cli"

  def project do
    [
      app: :corro_cli,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.2"},
      # Dev/test dependencies
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Elixir interface for Corrosion database CLI commands.
    
    Provides a comprehensive API for executing corrosion commands, parsing
    their concatenated JSON output, and handling uhlc NTP64 timestamps.
    """
  end

  defp package do
    [
      name: "corro_cli",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Corrosion Database" => "https://github.com/superfly/corrosion"
      },
      maintainers: ["Your Name <your@email.com>"]
    ]
  end

  defp docs do
    [
      main: "CorroCLI",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md"],
      groups_for_modules: [
        "Main API": [CorroCLI],
        "Parsing & Utilities": [
          CorroCLI.Parser,
          CorroCLI.TimeUtils,
          CorroCLI.Config
        ]
      ]
    ]
  end
end